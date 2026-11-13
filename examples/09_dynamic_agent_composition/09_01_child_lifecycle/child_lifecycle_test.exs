Code.require_file("child_lifecycle.ex", __DIR__)

defmodule Jido.Examples.MultiAgent.ChildLifecycleTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Agent.Ref
  alias Jido.AgentServer.{Snapshot, TurnResult}
  alias Jido.Examples.ChildLifecycle

  setup do
    id = System.unique_integer([:positive])
    instance = :"child_lifecycle_#{id}"
    namespace = "examples/child-lifecycle/#{id}"
    table = :"child_lifecycle_store_#{id}"

    start_supervised!(
      {Jido, name: instance, namespace: namespace, persistence: {Jido.Persistence.ETS, table: table}},
      id: instance
    )

    %{instance: instance, ref: Ref.new!(namespace: namespace, id: "worker")}
  end

  test "the Instance owns one logical Agent across activations", c do
    assert {:ok, c.ref} == Jido.create_agent(c.instance, c.ref, ChildLifecycle)
    assert {:ok, first} = Jido.activate_agent(c.instance, c.ref)

    assert {:ok, signal} = ChildLifecycle.increment_signal(%{})

    assert {:ok, %TurnResult{status: :committed, agent_revision: 1}} =
             Jido.call(c.instance, c.ref, signal)

    assert %Snapshot{agent: %{state: %{count: 1}}} = Jido.AgentServer.snapshot(first)
    assert {:ok, %Snapshot{agent: %{state: %{count: 1}}}} = Jido.AgentServer.stop(first)

    assert {:ok, second} = Jido.activate_agent(c.instance, c.ref)
    refute second == first
    assert %Snapshot{agent: %{state: %{count: 1}}} = Jido.AgentServer.snapshot(second)
  end
end
