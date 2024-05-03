defmodule PhoenixPubSubBuffered.TestSubscriber do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def subscribe(pubsub, topic) do
    GenServer.call(__MODULE__, {:subscribe, pubsub, topic})
  end

  def get_message() do
    GenServer.call(__MODULE__, :get_message)
  end

  @impl GenServer
  def init(_) do
    {:ok, []}
  end

  @impl GenServer
  def handle_call({:subscribe, pubsub, topic}, _from, messages) do
    Phoenix.PubSub.subscribe(pubsub, topic)
    {:reply, :ok, messages}
  end

  @impl GenServer
  def handle_call(:get_message, _from, messages) do
    {message, messages} = List.pop_at(messages, -1)
    {:reply, message, messages}
  end

  @impl GenServer
  def handle_info(message, buffer) do
    {:noreply, [message | buffer]}
  end
end
