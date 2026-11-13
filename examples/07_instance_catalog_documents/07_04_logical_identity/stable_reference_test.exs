Code.require_file("stable_reference.ex", __DIR__)

defmodule Jido.Examples.Runtime.StableReferenceTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  import Jido.Test.Eventually

  alias Jido.Agent.Ref
  alias Jido.Examples.StableReference
  alias Jido.Test.Persistence.ProbeStore

  setup do
    store = start_supervised!(ProbeStore)
    primary = :"ref_primary_#{System.unique_integer([:positive])}"
    other = :"ref_other_#{System.unique_integer([:positive])}"
    primary_namespace = "chat/primary/#{System.unique_integer([:positive])}"
    other_namespace = "chat/secondary/#{System.unique_integer([:positive])}"
    persistence = {ProbeStore, store: store}

    start_supervised!(
      {Jido, name: primary, namespace: primary_namespace, persistence: persistence},
      id: primary
    )

    start_supervised!(
      {Jido, name: other, namespace: other_namespace, persistence: persistence},
      id: other
    )

    ref = Ref.new!(namespace: primary_namespace, partition: "team-a", id: "conversation")

    %{
      store: persistence,
      primary: primary,
      other: other,
      ref: ref,
      other_namespace: other_namespace
    }
  end

  test "a saved Ref survives persistent process replacement", c do
    first = create_and_activate(c.primary, c.ref)

    assert :ok = Jido.AgentServer.await_ready(first)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             StableReference.append(c.ref, c.primary, "first")

    monitor = Process.monitor(first)
    Process.exit(first, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^first, _reason}, 1_000

    replacement =
      eventually(fn ->
        case Jido.resolve_agent(c.primary, c.ref) do
          {:ok, pid} when pid != first -> pid
          _result -> nil
        end
      end)

    assert replacement != first
    assert :ok = Jido.AgentServer.await_ready(replacement)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             StableReference.append(c.ref, c.primary, "second")

    assert Jido.AgentServer.snapshot(replacement).agent.state.messages == ["first", "second"]
  end

  test "equal IDs in separate namespaces reach separate conversations", c do
    other_ref = %{c.ref | namespace: c.other_namespace}

    _primary_server = create_and_activate(c.primary, c.ref)
    _other_server = create_and_activate(c.other, other_ref)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             StableReference.append(c.ref, c.primary, "A")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             StableReference.append(other_ref, c.other, "B")

    assert {:ok, first_server} = Jido.resolve_agent(c.primary, c.ref)
    assert {:ok, second_server} = Jido.resolve_agent(c.other, other_ref)
    assert Jido.AgentServer.snapshot(first_server).agent.state.messages == ["A"]
    assert Jido.AgentServer.snapshot(second_server).agent.state.messages == ["B"]
  end

  test "equal namespace and ID remain isolated by partition", c do
    other_partition = %{c.ref | partition: "team-b"}

    _team_a_server = create_and_activate(c.primary, c.ref)
    _team_b_server = create_and_activate(c.primary, other_partition)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             StableReference.append(c.ref, c.primary, "team A")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             StableReference.append(other_partition, c.primary, "team B")

    assert {:ok, first_server} = Jido.resolve_agent(c.primary, c.ref)
    assert {:ok, second_server} = Jido.resolve_agent(c.primary, other_partition)
    assert Jido.AgentServer.snapshot(first_server).agent.state.messages == ["team A"]
    assert Jido.AgentServer.snapshot(second_server).agent.state.messages == ["team B"]
  end

  test "a Ref round trips through its exact versioned public map", c do
    assert {:ok, encoded} = Ref.to_map(c.ref)

    assert encoded == %{
             "version" => 1,
             "namespace" => c.ref.namespace,
             "partition" => "team-a",
             "id" => "conversation"
           }

    assert {:ok, decoded} = Ref.from_map(encoded)
    assert decoded == c.ref
  end

  test "a Ref survives rebinding its namespace to another local instance", c do
    first = create_and_activate(c.primary, c.ref)

    assert :ok = Jido.AgentServer.await_ready(first)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             StableReference.append(c.ref, c.primary, "saved")

    assert {:ok, %Jido.AgentServer.Snapshot{}} = Jido.AgentServer.stop(first)
    refute Process.alive?(first)
    assert :ok = stop_supervised(c.primary)

    rebound = :"ref_rebound_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Jido, name: rebound, namespace: c.ref.namespace, persistence: c.store},
      id: rebound
    )

    assert {:ok, rebound_server} = Jido.activate_agent(rebound, c.ref)

    assert :ok = Jido.AgentServer.await_ready(rebound_server)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             StableReference.append(c.ref, rebound, "restored")

    assert Jido.AgentServer.snapshot(rebound_server).agent.state.messages == ["saved", "restored"]
  end

  defp create_and_activate(instance, ref) do
    assert {:ok, ^ref} = Jido.create_agent(instance, ref, StableReference)
    assert {:ok, server} = Jido.activate_agent(instance, ref)
    assert :ok = Jido.AgentServer.await_ready(server)
    server
  end
end
