defmodule JidoTest.Examples.StableReferenceTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.Examples.{StableReference, PersistenceProbeStore}
  alias StableReference.Conversation

  setup %{jido: jido} do
    store = start_supervised!(PersistenceProbeStore)
    other = :"ref_other_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: other})
    ref = %StableReference{namespace: "chat/primary", partition: "team-a", id: "conversation"}

    %{
      store: {PersistenceProbeStore, store: store},
      other: other,
      ref: ref,
      bindings: %{ref.namespace => jido}
    }
  end

  test "a saved application reference survives persistent process replacement", c do
    assert {:ok, first} =
             Jido.start_agent(c.jido, Conversation,
               id: c.ref.id,
               partition: c.ref.partition,
               persistence: c.store
             )

    assert {:ok, _} = StableReference.append(c.ref, c.bindings, "first")
    monitor = Process.monitor(first)
    Process.exit(first, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^first, _}, 1_000

    replacement =
      eventually(fn ->
        pid = Jido.whereis_agent(c.jido, c.ref.id, partition: c.ref.partition)
        if is_pid(pid) and pid != first, do: pid
      end)

    assert replacement != first
    assert {:ok, agent} = StableReference.append(c.ref, c.bindings, "second")
    assert agent.state.messages == ["first", "second"]
  end

  test "equal IDs in separate namespaces reach separate conversations", c do
    other_ref = %{c.ref | namespace: "chat/secondary"}
    bindings = Map.put(c.bindings, other_ref.namespace, c.other)

    for instance <- [c.jido, c.other] do
      assert {:ok, _} =
               Jido.start_agent(instance, Conversation, id: c.ref.id, partition: c.ref.partition)
    end

    assert {:ok, a} = StableReference.append(c.ref, bindings, "A")
    assert {:ok, b} = StableReference.append(other_ref, bindings, "B")
    assert a.state.messages == ["A"]
    assert b.state.messages == ["B"]
  end

  test "durable identity survives rebinding the same namespace to a new local instance", c do
    assert {:ok, first} =
             Jido.start_agent(c.jido, Conversation,
               id: c.ref.id,
               partition: c.ref.partition,
               persistence: c.store
             )

    assert {:ok, _} = StableReference.append(c.ref, c.bindings, "saved")
    assert :ok = Jido.hibernate(c.jido, first)

    assert {:ok, _} =
             Jido.thaw(c.other, Conversation, c.ref.id,
               partition: c.ref.partition,
               persistence: c.store
             )

    assert {:ok, agent} = StableReference.append(c.ref, %{c.ref.namespace => c.other}, "restored")
    assert agent.state.messages == ["saved", "restored"]
  end
end
