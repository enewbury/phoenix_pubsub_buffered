defmodule PhoenixPubSubBuffered.Cluster do
  def spawn_nodes(node_names) do
    node_names
    |> Enum.reduce([], fn name, nodes -> [spawn_node(name, nodes) | nodes] end)
    |> Enum.reverse()
  end

  def apply(node, module, fun, args) do
    :peer.call(node.pid, module, fun, args)
  end

  defmacro remote_run(node, args \\ [], do: block) do
    quote do
      pid = unquote(node).pid
      block = unquote(Macro.escape(block))
      {result, _binding} = :peer.call(pid, Code, :eval_quoted, [block, unquote(args)], 1000)
      result
    end
  end

  defmacro assert_peer_receive(peer, pattern, timeout \\ 5_000) do
    quote do
      start_time = System.monotonic_time()
      match_fn = fn message -> match?(unquote(pattern), message) end

      PhoenixPubSubBuffered.Cluster.remote_message_check(
        unquote(peer),
        match_fn,
        :assert,
        start_time,
        unquote(timeout)
      )
    end
  end

  defmacro refute_peer_receive(peer, pattern, timeout \\ 300) do
    quote do
      start_time = System.monotonic_time()
      match_fn = fn message -> match?(unquote(pattern), message) end

      PhoenixPubSubBuffered.Cluster.remote_message_check(
        unquote(peer),
        match_fn,
        :refute,
        start_time,
        unquote(timeout)
      )
    end
  end

  def remote_message_check(peer, match_fn, type, start_time, timeout, messages \\ []) do
    now = System.monotonic_time()

    message =
      remote_run peer do
        PhoenixPubSubBuffered.TestSubscriber.get_message()
      end

    messages = if not is_nil(message), do: messages ++ [message], else: messages

    case {match_fn.(message), type} do
      {true, :assert} ->
        true

      {true, :refute} ->
        ExUnit.Assertions.flunk("Found unexpected message #{inspect(message)}")

      {false, _type} when now - start_time < timeout ->
        Process.sleep(10)
        remote_message_check(peer, match_fn, type, start_time, timeout, messages)

      {false, :assert} ->
        ExUnit.Assertions.flunk(
          "Failed to find matching message in timeout, messages in mailbox #{inspect(messages)}"
        )

      {false, :refute} ->
        true
    end
  end

  def spawn_node(name, nodes) do
    {:ok, pid, node} = :peer.start_link(%{name: ~c"#{name}", connection: :standard_io})

    :peer.call(pid, :code, :add_paths, [:code.get_path()])
    connect_to_cluster(pid, nodes)
    transfer_config(pid)
    start_apps(pid)

    %{node: node, pid: pid}
  end

  defp connect_to_cluster(pid, [%{node: last_node} | _]) do
    :peer.call(pid, :net_kernel, :connect_node, [last_node])
  end

  defp connect_to_cluster(_pid, []), do: :ok

  defp transfer_config(pid) do
    # transfer app configuration
    Application.loaded_applications()
    |> Enum.map(fn {app_name, _, _} -> app_name end)
    |> Enum.map(fn app_name -> {app_name, Application.get_all_env(app_name)} end)
    |> Enum.each(fn {app_name, env} ->
      Enum.each(env, fn {key, val} ->
        :ok = :peer.call(pid, Application, :put_env, [app_name, key, val, [persistent: true]])
      end)
    end)
  end

  defp start_apps(pid) do
    :peer.call(pid, Application, :ensure_all_started, [:mix])
    :peer.call(pid, Mix, :env, [Mix.env()])

    for {app_name, _, _} <- Application.loaded_applications() do
      :peer.call(pid, Application, :ensure_all_started, [app_name])
    end

    remote_run %{pid: pid} do
      parent = self()

      spawn(fn ->
        children = [
          {Phoenix.PubSub,
           name: PubSubTest, adapter: PhoenixPubSubBuffered, pool_size: 1, buffer_size: 10},
          {PhoenixPubSubBuffered.TestSubscriber, name: PhoenixPubSubBuffered.TestSubscriber}
        ]

        {:ok, supervisor_pid} =
          Supervisor.start_link(children,
            strategy: :one_for_one,
            name: PhoenixPubSubBuffered.TestSupervisor
          )

        send(parent, {:started, supervisor_pid})

        Process.sleep(:infinity)
      end)

      receive do
        {:started, pid} -> {:ok, pid}
      end
    end
  end
end
