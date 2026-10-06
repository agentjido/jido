defmodule Jido.Topology.RuntimeCheckpointTest do
  use JidoTest.Case, async: true

  alias Jido.{AgentServer, Signal, Topology}
  alias Jido.Topology.Runtime
  alias JidoTest.AgentFixtures.CounterAgent

  for failure <- [:runtime, :director, :controller] do
    test "#{failure} failure keeps committed director and member state", c do
      id = unique_id("checkpoint_#{unquote(failure)}")
      start_supervised!({Runtime, options(c.jido, id, target())})
      assert {:ok, %{state: %{count: 7}}} = Runtime.call(c.jido, id, :counter, add(7))
      assert {:ok, %{state: %{count: 3}}} = AgentServer.call(Runtime.director(c.jido, id), add(3))
      failed = process(c.jido, id, unquote(failure))
      kill(failed)
      await_replacement(c.jido, id, unquote(failure), failed)

      assert :ok = Runtime.await_ready(c.jido, id)
      assert AgentServer.agent(Runtime.director(c.jido, id)).state.count == 3
      assert {:ok, %{state: %{count: 8}}} = Runtime.call(c.jido, id, :counter, add())
    end
  end

  test "clean stop clears a checkpoint whose member is dormant after Runtime recovery", c do
    id = unique_id("dormant_checkpoint")
    opts = options(c.jido, id, target())
    root = start_supervised!({Runtime, opts})
    assert {:ok, %{state: %{count: 7}}} = Runtime.call(c.jido, id, :counter, add(7))
    kill(root)
    await_replacement(c.jido, id, :runtime, root)
    assert :ok = Runtime.await_ready(c.jido, id)
    assert Runtime.whereis_member(c.jido, id, :counter) == nil
    assert :ok = stop_supervised({Runtime, id})
    start_supervised!({Runtime, opts})
    assert {:ok, %{state: %{count: 1}}} = Runtime.call(c.jido, id, :counter, add())
  end

  for failure <- [:runtime, :director] do
    test "#{failure} failure keeps nested child state and clean stop clears it", c do
      id = unique_id("nested_checkpoint_#{unquote(failure)}")
      opts = options(c.jido, id, nested_target())
      start_supervised!({Runtime, opts})
      assert {:ok, %{state: %{count: 7}}} = Runtime.call(c.jido, id, {:child, :team}, add(7))
      failed = process(c.jido, id, unquote(failure))
      kill(failed)
      await_replacement(c.jido, id, unquote(failure), failed)

      assert :ok = Runtime.await_ready(c.jido, id)
      assert {:ok, %{state: %{count: 8}}} = Runtime.call(c.jido, id, {:child, :team}, add())
      assert :ok = stop_supervised({Runtime, id})
      start_supervised!({Runtime, opts})
      assert {:ok, %{state: %{count: 1}}} = Runtime.call(c.jido, id, {:child, :team}, add())
    end
  end

  test "clean parent stop clears nested checkpoints while the child branch is dormant", c do
    id = unique_id("dormant_nested_checkpoint")
    opts = options(c.jido, id, nested_target())
    root = start_supervised!({Runtime, opts})
    assert {:ok, %{state: %{count: 7}}} = Runtime.call(c.jido, id, {:child, :team}, add(7))
    kill(root)
    await_replacement(c.jido, id, :runtime, root)
    assert :ok = Runtime.await_ready(c.jido, id)
    assert Runtime.whereis_child(c.jido, id, :team) == nil
    assert :ok = stop_supervised({Runtime, id})
    start_supervised!({Runtime, opts})
    assert {:ok, %{state: %{count: 1}}} = Runtime.call(c.jido, id, {:child, :team}, add())
  end

  test "a clean child stop clears checkpoints after its GateServer restarts", c do
    id = unique_id("replaced_gate_checkpoint")
    topology = Topology.new!(name: "parent", children: [child(target(), :counter)])
    start_supervised!({Runtime, options(c.jido, id, topology)})
    assert {:ok, %{state: %{count: 7}}} = Runtime.call(c.jido, id, {:child, :team}, add(7))
    child = Runtime.whereis_child(c.jido, id, :team)
    gate = Runtime.lookup(c.jido, id, {:gate, "team"})
    kill(gate)

    eventually(fn ->
      replacement = Runtime.lookup(c.jido, id, {:gate, "team"})
      is_pid(replacement) and replacement != gate
    end)

    assert Runtime.whereis_child(c.jido, id, :team) == child
    assert {:ok, %{state: %{count: 8}}} = Runtime.call(c.jido, id, {:child, :team}, add())
    assert :ok = Supervisor.stop(child)

    child_id = id <> "/child/team"
    start_supervised!({Runtime, options(c.jido, child_id, target())})
    assert {:ok, %{state: %{count: 1}}} = Runtime.call(c.jido, child_id, :counter, add())
  end

  test "a parent never waits for or deletes an independent Runtime at its declared child ID", c do
    id = unique_id("checkpoint_alias")
    independent_id = id <> "/child/team"
    leaf = Topology.new!(name: "independent", agents: [%{key: :counter, module: CounterAgent}])

    independent =
      start_supervised!(
        {Runtime, jido: c.jido, id: independent_id, topology: leaf, activation: :lazy}
      )

    signal = Signal.new!("counter.add", %{by: 7, label: "alias"}, source: "/test")
    assert {:ok, %{state: %{count: 7}}} = Runtime.call(c.jido, independent_id, :counter, signal)

    parent =
      Topology.new!(
        name: "parent",
        children: [
          %{
            key: :team,
            topology: leaf,
            gate: %{commands: [%{type: "counter.add", member: :counter}]}
          }
        ]
      )

    start_supervised!({Runtime, jido: c.jido, id: id, topology: parent, activation: :lazy})
    assert :ok = Runtime.await_ready(c.jido, id)
    assert :ok = stop_supervised({Runtime, id})
    assert Process.alive?(independent)
    assert :ok = Runtime.Owner.await_previous(c.jido, id)

    # A failed independent runtime still needs its own committed checkpoint.
    kill(independent)
    await_replacement(c.jido, independent_id, :runtime, independent)

    assert :ok = Runtime.await_ready(c.jido, independent_id)
    signal = %{signal | data: %{by: 1, label: "alias"}}
    assert {:ok, %{state: %{count: 8}}} = Runtime.call(c.jido, independent_id, :counter, signal)
  end

  test "definition preparation validates and resets the RuntimeCheckpoint fallback", c do
    id = unique_id("fallback-definition")
    topology = Topology.new!(name: "fallback_definition")

    start_supervised!(
      {Runtime, jido: c.jido, id: id, topology: topology, activation: :lazy, repair: :manual}
    )

    source = CounterAgent.definition()
    compatible = %{source | description: "compatible candidate"}

    assert :ok =
             Runtime.add_agent(c.jido, id, :actor, source,
               initial_state: %{count: 4, history: []}
             )

    assert {:ok, %{state: %{count: 7}}} = Runtime.call(c.jido, id, :actor, add(3))
    assert :ok = Runtime.remove_agent(c.jido, id, :actor)

    assert :ok =
             Runtime.prepare_agent_definition(
               c.jido,
               id,
               :actor,
               source,
               compatible,
               :preserve,
               initial_state: %{count: 1, history: []}
             )

    physical_id = id <> "/agent/actor"
    key = Jido.partition_key(physical_id, nil)

    assert {:ok, %{agent: preserved, state_version: 1} = before} =
             Jido.RuntimeStore.fetch(c.jido, :agent_runtime_checkpoints, key)

    assert preserved.state == %{count: 7, history: ["checkpoint"]}

    incompatible = %{
      source
      | schema:
          Zoi.object(%{
            count: Zoi.string() |> Zoi.default("zero"),
            history: Zoi.list(Zoi.string()) |> Zoi.default([])
          })
    }

    assert {:error, %Jido.Error.ValidationError{}} =
             Runtime.prepare_agent_definition(
               c.jido,
               id,
               :actor,
               source,
               incompatible,
               :preserve,
               initial_state: %{count: "reset", history: []}
             )

    assert {:ok, ^before} =
             Jido.RuntimeStore.fetch(c.jido, :agent_runtime_checkpoints, key)

    candidate = %{source | description: "reset candidate"}
    initial_state = %{count: 2, history: []}

    tasks =
      for _index <- 1..2 do
        Task.async(fn ->
          Runtime.prepare_agent_definition(
            c.jido,
            id,
            :actor,
            source,
            candidate,
            :reset,
            initial_state: initial_state
          )
        end)
      end

    assert Enum.map(tasks, &Task.await/1) == [:ok, :ok]

    assert {:ok, %{agent: prepared, state_version: 2, owner: owner} = reset} =
             Jido.RuntimeStore.fetch(c.jido, :agent_runtime_checkpoints, key)

    assert prepared.state == initial_state
    assert prepared.description == "reset candidate"
    assert match?({_node, _scope}, owner)

    assert :ok =
             Runtime.prepare_agent_definition(
               c.jido,
               id,
               :actor,
               source,
               candidate,
               :reset,
               initial_state: initial_state
             )

    assert {:ok, ^reset} = Jido.RuntimeStore.fetch(c.jido, :agent_runtime_checkpoints, key)
    assert Runtime.target(c.jido, id).definition.agents == []
    assert Runtime.whereis_member(c.jido, id, :actor) == nil
  end

  test "definition preparation handles a missing RuntimeCheckpoint without a tombstone", c do
    id = unique_id("missing-fallback-definition")
    topology = Topology.new!(name: "missing_fallback_definition")

    start_supervised!(
      {Runtime, jido: c.jido, id: id, topology: topology, activation: :lazy, repair: :manual}
    )

    source = CounterAgent.definition()
    candidate = %{source | description: "candidate"}
    physical_id = id <> "/agent/actor"
    key = Jido.partition_key(physical_id, nil)

    assert :ok =
             Runtime.prepare_agent_definition(
               c.jido,
               id,
               :actor,
               source,
               candidate,
               :preserve,
               initial_state: %{count: 3, history: []}
             )

    assert :error = Jido.RuntimeStore.fetch(c.jido, :agent_runtime_checkpoints, key)

    assert :ok =
             Runtime.prepare_agent_definition(
               c.jido,
               id,
               :actor,
               source,
               candidate,
               :reset,
               initial_state: %{count: 3, history: []}
             )

    assert {:ok, %{agent: %{state: %{count: 3}}, state_version: 0}} =
             Jido.RuntimeStore.fetch(c.jido, :agent_runtime_checkpoints, key)
  end

  defp target,
    do: Topology.new!(name: "checkpoints", agents: [%{key: :counter, module: CounterAgent}])

  defp nested_target do
    middle = Topology.new!(name: "middle", children: [child(target(), :counter)])
    Topology.new!(name: "root", children: [child(middle, {:child, :team})])
  end

  defp child(topology, member) do
    %{
      key: :team,
      topology: topology,
      gate: %{commands: [%{type: "counter.add", member: member}]}
    }
  end

  defp options(jido, id, topology),
    do: [
      jido: jido,
      id: id,
      topology: topology,
      director: CounterAgent.definition(),
      activation: :lazy
    ]

  defp process(jido, id, :runtime), do: Runtime.whereis_runtime(jido, id)
  defp process(jido, id, :director), do: Runtime.director(jido, id)
  defp process(jido, id, :controller), do: Runtime.controller(jido, id)

  defp await_replacement(jido, id, role, previous) do
    eventually(
      fn ->
        replacement = process(jido, id, role)

        is_pid(replacement) and replacement != previous and
          is_list(Supervisor.which_children(Runtime.whereis_runtime(jido, id))) and
          is_pid(Runtime.controller(jido, id)) and is_pid(Runtime.lookup(jido, id, :gateway))
      end,
      timeout: 5_000
    )
  end

  defp kill(pid) do
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5_000
  end

  defp add(count \\ 1),
    do: Signal.new!("counter.add", %{by: count, label: "checkpoint"}, source: "/test")
end
