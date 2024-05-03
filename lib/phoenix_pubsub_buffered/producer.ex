defmodule PhoenixPubSubBuffered.Producer do
  @moduledoc false
  use GenServer

  def start_link({buffer_size, group}) do
    GenServer.start_link(__MODULE__, {buffer_size, group}, name: name(group))
  end

  def buffer_and_send(group, message) do
    GenServer.call(name(group), {:write, message})
  end

  def name(group) do
    Module.concat(group, Producer)
  end

  defp pg_members(group) do
    :pg.get_members(Phoenix.PubSub, group)
  end

  @impl GenServer
  def init({buffer_size, group}) do
    {_ref, pids} = :pg.monitor(Phoenix.PubSub, group)

    Enum.each(pids, &GenServer.call(&1, {:register, node()}))

    state = %{
      group: group,
      write_cursor: 0,
      read_cursors: Map.new(pids, &{node(&1), 0}),
      buffer: :array.new(buffer_size)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:write, message}, _from, state) do
    remote_pids = pg_members(state.group)

    for pid <- remote_pids, do: send(self(), {:flush, pid})

    i = rem(state.write_cursor, :array.size(state.buffer))
    buffer = :array.set(i, message, state.buffer)
    state = %{state | buffer: buffer, write_cursor: state.write_cursor + 1}

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({_ref, :join, _group, new_pids}, state) do
    state = Enum.reduce(new_pids, state, &process_joined(&1, &2))
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({_ref, :leave, _group, _leaving}, state), do: {:noreply, state}

  @impl GenServer
  def handle_info({:flush, pid}, state) do
    cursor = Map.get(state.read_cursors, node(pid), 0)
    {:noreply, send_messages(pid, cursor, state)}
  end

  defp process_joined(pid, state) do
    node = node(pid)

    if Map.has_key?(state.read_cursors, node) do
      resume(pid, node, state)
    else
      GenServer.call(pid, {:register, node()})
      %{state | read_cursors: Map.put(state.read_cursors, node, state.write_cursor)}
    end
  end

  defp resume(pid, node, state) do
    oldest = max(state.write_cursor - :array.size(state.buffer), 0)

    case Map.get(state.read_cursors, node, 0) do
      cursor when cursor == state.write_cursor -> state
      cursor when cursor < oldest -> send_expired(pid, state)
      cursor -> send_messages(pid, cursor, state)
    end
  end

  defp send_messages(pid, cursor, state) do
    %{read_cursors: read_cursors, write_cursor: write_cursor} = state

    messages =
      cursor..(write_cursor - 1)
      |> Enum.reduce([], fn cursor, acc -> [get_message(cursor, state) | acc] end)
      |> Enum.reverse()

    if GenServer.call(pid, messages) == :ok,
      do: %{state | read_cursors: Map.put(read_cursors, node(pid), write_cursor)},
      else: state
  end

  defp send_expired(pid, state) do
    GenServer.call(pid, {:expired, node()})
    Map.update!(state, :read_cursors, &Map.delete(&1, node(pid)))
  end

  defp get_message(cursor, state) do
    i = rem(cursor, :array.size(state.buffer))
    :array.get(i, state.buffer)
  end
end
