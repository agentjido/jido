defmodule JidoTest.Examples.Research.ChildTopologyLifecycleTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.ChildTopologyRuntimeAssertions

  alias Jido.AgentServer
  alias Jido.Examples.Research.ChildTopologyRuntime.Specifications

  test "the parent director receives one aggregate child state, with no private child events",
       c do
    assert {:ok, definition} = Specifications.parent(:dsl, :dsl)
    id = unique_id("child-lifecycle")
    parent = start_supervised!({runtime(), opts(c.jido, id, definition)})

    try do
      assert {:ok, _} = call_child(c.jido, id)
      assert :ok = rpc(:await_gate_idle, [c.jido, id, :team, 5_000])
      director = rpc(:director, [c.jido, id])
      child = child_id(id)

      eventually(fn ->
        Enum.any?(AgentServer.agent(director).state.events, fn event ->
          event.type == "jido.topology.lifecycle.child.status_changed" and
            event.data == %{child: "team", id: child, status: :ready}
        end)
      end)

      child_director = rpc(:director, [c.jido, child])
      eventually(fn -> AgentServer.agent(child_director).state.events != [] end)
      child_events = AgentServer.agent(child_director).state.events
      assert child_events != []
      parent_events = AgentServer.agent(director).state.events
      refute Enum.any?(parent_events, &(&1 in child_events))

      assert %{children: %{"team" => %{status: :ready}}, ready?: true} =
               rpc(:status, [c.jido, id])
    after
      stop_runtime(c.jido, id, parent)
    end
  end

  test "a child member restart restores state without restarting either director", c do
    assert {:ok, definition} = Specifications.parent(:data, :dsl)
    id = unique_id("child-member-restart")
    parent = start_supervised!({runtime(), opts(c.jido, id, definition)})

    try do
      assert {:ok, committed} = call_child(c.jido, id, 7)
      child = child_id(id)
      parent_director = rpc(:director, [c.jido, id])
      child_director = rpc(:director, [c.jido, child])
      alice = rpc(:whereis_member, [c.jido, child, :alice])
      kill(alice)

      eventually(fn ->
        replacement = rpc(:whereis_member, [c.jido, child, :alice])
        is_pid(replacement) and replacement != alice
      end)

      assert :ok = rpc(:await_ready, [c.jido, child, 5_000])
      replacement = rpc(:whereis_member, [c.jido, child, :alice])
      assert AgentServer.agent(replacement) == committed
      assert rpc(:director, [c.jido, id]) == parent_director
      assert rpc(:director, [c.jido, child]) == child_director
      assert rpc(:whereis_member, [c.jido, child, :bob]) == nil
    after
      stop_runtime(c.jido, id, parent)
    end
  end

  test "child runtime failure restores the child and leaves the parent running", c do
    assert {:ok, definition} = Specifications.parent(:dsl, :dsl)
    id = unique_id("child-runtime-restart")
    parent = start_supervised!({runtime(), opts(c.jido, id, definition)})

    try do
      assert {:ok, _} = call_child(c.jido, id, 7)
      director = rpc(:director, [c.jido, id])
      child = rpc(:whereis_child, [c.jido, id, :team])
      kill(child)

      eventually(fn ->
        replacement = rpc(:whereis_child, [c.jido, id, :team])
        is_pid(replacement) and replacement != child
      end)

      assert rpc(:director, [c.jido, id]) == director
      assert Process.alive?(parent)
      assert {:ok, %{state: %{total: 8}}} = call_child(c.jido, id)
      assert rpc(:whereis_member, [c.jido, child_id(id), :bob]) == nil
    after
      stop_runtime(c.jido, id, parent)
    end
  end

  test "a child restart limit leaves a failed gate without restarting the parent", c do
    assert {:ok, definition} = Specifications.parent(:data, :dsl, max_restarts: 0)
    id = unique_id("child-restart-limit")
    parent = start_supervised!({runtime(), opts(c.jido, id, definition)})

    try do
      assert {:ok, _} = call_child(c.jido, id)
      kill(rpc(:whereis_child, [c.jido, id, :team]))

      eventually(fn ->
        match?(%{children: %{"team" => %{status: :failed}}}, rpc(:status, [c.jido, id]))
      end)

      assert Process.alive?(parent)
      assert rpc(:whereis_child, [c.jido, id, :team]) == nil
      assert {:error, :child_restart_limit} = call_child(c.jido, id)

      assert %{ready?: false, children: %{"team" => %{status: :failed}}} =
               rpc(:status, [c.jido, id])
    after
      stop_runtime(c.jido, id, parent)
    end
  end

  test "an expired first-call deadline returns a bounded error without delivering the command",
       c do
    assert {:ok, definition} = Specifications.parent(:dsl, :dsl)
    id = unique_id("child-deadline")
    parent = start_supervised!({runtime(), opts(c.jido, id, definition)})

    try do
      assert :ok = rpc(:await_ready, [c.jido, id, 5_000])
      assert {:error, :activation_timeout} = call_child(c.jido, id, 99, timeout: 0)
      assert {:ok, %{state: %{total: 1}}} = call_child(c.jido, id)
    after
      stop_runtime(c.jido, id, parent)
    end
  end

  test "parent shutdown stops the child director, Controller, members, and Bus", c do
    assert {:ok, definition} = Specifications.parent(:data, :dsl)
    id = unique_id("owned-child-shutdown")
    parent = start_supervised!({runtime(), opts(c.jido, id, definition)})
    assert {:ok, _} = call_child(c.jido, id)
    stop_runtime(c.jido, id, parent)
    assert rpc(:whereis_child, [c.jido, id, :team]) == nil
    assert rpc(:whereis_runtime, [c.jido, child_id(id)]) == nil
  end

  test "Jido restart restores a stored child member through the same parent gate", c do
    assert {:ok, definition} = Specifications.parent(:data, :data_agents)
    id = unique_id("persistent-child")
    durable = :"persistent_child_#{c.jido}"

    jido_opts = [
      name: durable,
      namespace: Atom.to_string(durable),
      persistence: {Jido.Persistence.ETS, table: durable}
    ]

    start_supervised!({Jido, jido_opts}, id: durable)
    parent = start_supervised!({runtime(), opts(durable, id, definition)})
    assert {:ok, committed} = call_child(durable, id, 7)
    alice = rpc(:whereis_member, [durable, child_id(id), :alice])
    assert Process.alive?(parent)
    stop_supervised!({runtime(), id})
    stop_supervised!(durable)
    start_supervised!({Jido, jido_opts}, id: durable)
    parent = start_supervised!({runtime(), opts(durable, id, definition)})

    try do
      assert :ok = rpc(:await_ready, [durable, id, 5_000])
      assert rpc(:whereis_child, [durable, id, :team]) == nil
      assert {:ok, restored} = call_child(durable, id)
      assert restored.state.total == committed.state.total + 1
      assert restored.schema == committed.schema
      assert restored.routes == committed.routes
      assert restored.metadata == committed.metadata
      assert rpc(:whereis_member, [durable, child_id(id), :alice]) != alice
      assert rpc(:whereis_member, [durable, child_id(id), :bob]) == nil
    after
      stop_runtime(durable, id, parent)
    end
  end
end
