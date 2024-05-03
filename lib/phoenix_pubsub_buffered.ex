defmodule PhoenixPubSubBuffered do
  @moduledoc """
  Phoenix PubSub adapter using :pg with at-least-once delivery.

  To start it, list it in your supervision tree as:

      {Phoenix.PubSub, name: MyApp.PubSub, adapter: PhoenixPubSubBuffered}

  You will also need to add `:phoenix_pubsub_buffered` to your deps:

      defp deps do
        [{:phoenix_pubsub_buffered, "~> 0.1.0"}]
      end

  ## Options

    * `:name` - The required name to register the PubSub processes, ie: `MyApp.PubSub`
    * `:pool_size` - The number of producers and workers to run on each node, allowing concurrent message delivery.
    * `:buffer_size` - The amount of messages to maintain in memory

  ## Implementation

  The in memory buffer is a ring buffer, meaning that a constant number of messages are maintained and once
  the buffer is full, new messages overwrite the oldest message in the buffer.

  This means that if a node in the cluster is disconnected long enough that when it reconnects, its cursor
  points to a message that no longer exists, it will receive a special message over pubsub: `{:cursor_expired, node@host}`

  Applications are encouraged to handle and act on this message to get to a valid state, such as reloading all state from
  a source of truth like the db or another node. While this technically means that we don't guarentee every node will
  receive every message, we can guerentee that there are no gaps in messages. Recipt of message 3 guarentees you've
  received messages 1 and 2.

  """
  @behaviour Phoenix.PubSub.Adapter

  use Supervisor

  alias PhoenixPubSubBuffered.Producer
  alias PhoenixPubSubBuffered.Worker
  alias Phoenix.PubSub.Adapter

  ## Adapter callbacks

  @impl Adapter
  def node_name(_), do: node()

  @impl Adapter
  def broadcast(adapter_name, topic, message, dispatcher) do
    group = group(adapter_name)
    message = forward_to_local(topic, message, dispatcher)

    Producer.buffer_and_send(group, message)
  end

  @impl Adapter
  def direct_broadcast(adapter_name, node_name, topic, message, dispatcher) do
    GenServer.call(
      {Module.concat(group(adapter_name), :Worker), node_name},
      {:forward_to_local, topic, message, dispatcher}
    )
  end

  defp forward_to_local(topic, message, dispatcher) do
    {:forward_to_local, topic, message, dispatcher}
  end

  defp group(adapter_name) do
    groups = :persistent_term.get(adapter_name)
    elem(groups, :erlang.phash2(self(), tuple_size(groups)))
  end

  ## Supervisor callbacks

  @doc false
  def start_link(opts) do
    adapter_name = Keyword.fetch!(opts, :adapter_name)
    Supervisor.start_link(__MODULE__, opts, name: Module.concat(adapter_name, Supervisor))
  end

  @impl Supervisor
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    adapter_name = Keyword.fetch!(opts, :adapter_name)
    pool_size = Keyword.get(opts, :pool_size, 1)
    buffer_size = Keyword.get(opts, :buffer_size, 10_000)

    [_ | groups] =
      for number <- 1..pool_size do
        :"#{adapter_name}#{number}"
      end

    # Use `adapter_name` for the first in the pool for backwards compatability
    # with v2.0 when the pool_size is 1.
    groups = [adapter_name | groups]

    :persistent_term.put(adapter_name, List.to_tuple(groups))

    children =
      Enum.flat_map(groups, fn group ->
        producer_id = Module.concat(group, Producer)

        [
          Supervisor.child_spec({Producer, {buffer_size, group}}, id: producer_id),
          Supervisor.child_spec({Worker, {name, group}}, id: Module.concat(group, :Worker))
        ]
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
