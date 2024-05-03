defmodule PhoenixPubSubBufferedTest do
  use ExUnit.Case

  import PhoenixPubSubBuffered.Cluster

  doctest PhoenixPubSubBuffered

  setup do
    [peer1, peer2] = spawn_nodes(["node1", "node2"])

    remote_run peer2 do
      PhoenixPubSubBuffered.TestSubscriber.subscribe(PubSubTest, "topic")
    end

    %{peer1: peer1, peer2: peer2}
  end

  test "receives broadcast message on all connected nodes", %{peer1: peer1, peer2: peer2} do
    peer3 = spawn_node("node3", [peer1])
    remote_run peer3, do: PhoenixPubSubBuffered.TestSubscriber.subscribe(PubSubTest, "topic")
    remote_run peer1, do: Phoenix.PubSub.broadcast!(PubSubTest, "topic", :message)
    assert_peer_receive peer2, :message
    assert_peer_receive peer3, :message
  end

  test "direct_broadcast targets a specific node", %{peer1: peer1, peer2: peer2} do
    peer3 = spawn_node("node3", [peer1])
    remote_run peer3, do: PhoenixPubSubBuffered.TestSubscriber.subscribe(PubSubTest, "topic")

    remote_run peer1, node: peer3.node do
      Phoenix.PubSub.direct_broadcast!(node, PubSubTest, "topic", :message)
    end

    refute_peer_receive peer2, :message
    assert_peer_receive peer3, :message
  end

  test "catches up with messages after disconnect", %{peer1: peer1, peer2: peer2} do
    remote_run peer1, do: Phoenix.PubSub.broadcast!(PubSubTest, "topic", 1)
    assert_peer_receive peer2, 1

    remote_run peer2, node: peer1.node do
      Node.disconnect(node)
    end

    remote_run peer1, do: Phoenix.PubSub.broadcast!(PubSubTest, "topic", 2)
    remote_run peer1, do: Phoenix.PubSub.broadcast!(PubSubTest, "topic", 3)

    remote_run peer2, node: peer1.node do
      Node.connect(node)
    end

    assert_peer_receive peer2, 2
    assert_peer_receive peer2, 3
  end

  test "new client only reads new messages", %{peer1: peer1} do
    remote_run peer1, do: Phoenix.PubSub.broadcast!(PubSubTest, "topic", 1)
    peer3 = spawn_node("node3", [peer1])

    remote_run peer3 do
      PhoenixPubSubBuffered.TestSubscriber.subscribe(PubSubTest, "topic")
    end

    remote_run(peer1, do: Phoenix.PubSub.broadcast!(PubSubTest, "topic", 2))
    assert_peer_receive peer3, 2
  end

  test "gets 'expired' message when read cursor is too old", %{peer1: peer1, peer2: peer2} do
    remote_run peer2, node: peer1.node do
      Node.disconnect(node)
    end

    remote_run peer1 do
      for i <- 1..11 do
        Phoenix.PubSub.broadcast!(PubSubTest, "topic", i)
      end
    end

    remote_run peer2, node: peer1.node do
      Node.connect(node)
    end

    node = peer1.node
    assert_peer_receive peer2, {:cursor_expired, ^node}
  end

  test "workers get 'expired' if producer loses state", %{peer1: peer1, peer2: peer2} do
    remote_run peer2, node: peer1.node do
      Node.disconnect(node)
    end

    remote_run peer1 do
      GenServer.stop(PubSubTest.Adapter.Producer, :normal)
    end

    remote_run peer2, node: peer1.node do
      Node.connect(node)
    end

    node = peer1.node
    assert_peer_receive peer2, {:cursor_expired, ^node}
  end
end
