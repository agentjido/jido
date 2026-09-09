defmodule JidoTest.Examples.StableReferenceTest do
  use ExUnit.Case, async: true
  @moduletag :example

  import JidoTest.Eventually

  alias Jido.Agent.Ref
  alias Jido.Examples.{StableReference, PersistenceProbeStore}
  alias StableReference.Conversation

  setup do
    store = start_supervised!(PersistenceProbeStore)
    primary = :"ref_primary_#{System.unique_integer([:positive])}"
    other = :"ref_other_#{System.unique_integer([:positive])}"
    primary_namespace = "chat/primary/#{System.unique_integer([:positive])}"
    other_namespace = "chat/secondary/#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: primary, namespace: primary_namespace}, id: primary)
    start_supervised!({Jido, name: other, namespace: other_namespace}, id: other)

    ref =
      Ref.new!(namespace: primary_namespace, partition: "team-a", id: "conversation")

    %{
      store: {PersistenceProbeStore, store: store},
      primary: primary,
      other: other,
      ref: ref,
      other_namespace: other_namespace
    }
  end

  test "a saved application reference survives persistent process replacement", c do
    assert {:ok, first} =
             Jido.start_agent_ref(c.primary, c.ref, Conversation, persistence: c.store)

    assert {:ok, _} = StableReference.append(c.ref, c.primary, "first")
    monitor = Process.monitor(first)
    Process.exit(first, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^first, _}, 1_000

    replacement =
      eventually(fn ->
        case Jido.resolve_agent(c.primary, c.ref) do
          {:ok, pid} when pid != first -> pid
          _result -> nil
        end
      end)

    assert replacement != first
    assert {:ok, agent} = StableReference.append(c.ref, c.primary, "second")
    assert agent.state.messages == ["first", "second"]
  end

  test "equal IDs in separate namespaces reach separate conversations", c do
    other_ref = %{c.ref | namespace: c.other_namespace}

    assert {:ok, _} = Jido.start_agent_ref(c.primary, c.ref, Conversation)
    assert {:ok, _} = Jido.start_agent_ref(c.other, other_ref, Conversation)

    assert {:ok, a} = StableReference.append(c.ref, c.primary, "A")
    assert {:ok, b} = StableReference.append(other_ref, c.other, "B")
    assert a.state.messages == ["A"]
    assert b.state.messages == ["B"]
  end

  test "durable identity survives rebinding the same namespace to a new local instance", c do
    assert {:ok, first} =
             Jido.start_agent_ref(c.primary, c.ref, Conversation, persistence: c.store)

    assert {:ok, _} = StableReference.append(c.ref, c.primary, "saved")
    assert :ok = Jido.hibernate_ref(c.primary, c.ref)
    refute Process.alive?(first)
    assert :ok = stop_supervised(c.primary)

    rebound = :"ref_rebound_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: rebound, namespace: c.ref.namespace}, id: rebound)

    assert {:ok, _} = Jido.activate_agent(rebound, c.ref, Conversation, persistence: c.store)

    assert {:ok, agent} = StableReference.append(c.ref, rebound, "restored")
    assert agent.state.messages == ["saved", "restored"]
  end
end
