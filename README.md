# PhoenixPubSubBuffered

A Phoenix.PubSub adapter that distributes messages between nodes using the erlang `:pg` module, like the default adapter, however with the additional guarentees of "at least once" delivery. 

This means that you can have nodes dissconnect temporarily from the cluster, and then "catch up" when they rejoin by maintaining a buffer of messages, and read cursors.

See the docs for more information.

## Usage


```elixir
def deps do
  [
    {:phoenix_pubsub_buffered, "~> 0.1.0"}
  ]
end

# application.ex
children = [
  # ...,
  {Phoenix.PubSub, name: MyApp.PubSub, adapter: PhoenixPubSubBuffered}
]
```

Config Options

Option                  | Description                                                               | Default        |
:-----------------------| :------------------------------------------------------------------------ | :------------- |
`:name`                 | The required name to register the PubSub processes, ie: `MyApp.PubSub`    |                |
`:pool_size`            | Determines the number of workers and producers on each node               | 1              |
`:buffer_size`          | The numbers of messages to hold in memory for each producer in the pool   | 10_000         |

Subscribing processes should handle the message `{:cursor_expired, node_name}` which indicates that your client
has been disconnected long enough that your position in the broadcaster's buffer has been overwritten. At this point it is the subscribing process's job to return to a valid state i.e. reloading state from source like database or another node.

