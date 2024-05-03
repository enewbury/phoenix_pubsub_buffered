defmodule PhoenixPubSubBuffered.Worker do
  @moduledoc false
  use GenServer

  def start_link({name, group}) do
    GenServer.start_link(__MODULE__, {name, group}, name: Module.concat(group, Worker))
  end

  @impl true
  def init({name, group}) do
    :ok = pg_join(group)
    {:ok, %{pubsub: name, registrations: MapSet.new()}}
  end

  @impl true
  def handle_call({:forward_to_local, topic, message, dispatcher}, _from, state) do
    Phoenix.PubSub.local_broadcast(state.pubsub, topic, message, dispatcher)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call([{:forward_to_local, _, _, _} | _] = messages, from, state) do
    Enum.each(messages, fn message -> handle_call(message, from, state) end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:register, node}, _from, state) do
    if MapSet.member?(state.registrations, node),
      do: broadcast_expired_message(state.pubsub, node)

    {:reply, :ok, %{state | registrations: MapSet.put(state.registrations, node)}}
  end

  @impl true
  def handle_call({:registered?, node}, _from, state) do
    {:reply, MapSet.member?(state.registrations, node), state}
  end

  @impl true
  def handle_call({:expired, node}, _from, state) do
    broadcast_expired_message(state.pubsub, node)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(_, _from, state) do
    {:reply, {:error, :bad_message}, state}
  end

  defp broadcast_expired_message(pubsub, node) do
    topics = Registry.select(pubsub, [{{:"$1", :_, :_}, [], [:"$1"]}])

    Enum.each(topics, fn topic ->
      Phoenix.PubSub.local_broadcast(pubsub, topic, {:cursor_expired, node})
    end)
  end

  defp pg_join(group) do
    :ok = :pg.join(Phoenix.PubSub, group, self())
  end
end
