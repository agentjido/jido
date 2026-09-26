defmodule JidoTest.System.Scenarios.Topology do
  @moduledoc false
  defmacro __using__(_opts) do
    quote location: :keep do
      alias Jido.AgentServer, as: Server
      alias Jido.Examples.Topology.Cell
      alias Jido.Signal.Bus
      alias Jido.Topology.Controller
      alias Jido.Topology.Controller.Runtime
      alias Jido.Tracing.Trace
      alias JidoTest.System.Observability

      test "included teams retain owned checkpoints and subscriptions across shared Bus replacement",
           c do
        alias Jido.Examples.Topology.ComposedSystem
        alias Jido.Topology.Ref

        initial = ComposedSystem.new!(id: c.namespace, input: %{east_workers: 1, west_workers: 1})
        controller = start_controller(c, initial)
        director = Controller.whereis_agent(controller, :director)

        leaders =
          for team <- [:east, :west] do
            Controller.whereis_agent(controller, Ref.ref(team, :leader))
          end

        workers =
          for team <- [:east, :west] do
            Controller.whereis_agent(controller, Ref.ref(team, :workers), 1)
          end

        owned = [director | leaders ++ workers]
        assert Enum.all?(owned, &is_pid/1)
        assert Enum.all?(leaders, fn leader -> leader in child_pids(director) end)

        for {leader, worker} <- Enum.zip(leaders, workers) do
          assert(worker in child_pids(leader))
        end

        bus = Controller.whereis_bus(controller, :events)
        {:ok, first} = Cell.work_signal(%{value: 7})
        assert {:ok, [_]} = Bus.publish(bus, [first])

        for worker <- workers do
          Observability.await_turn(c.observer, worker, 1)
        end

        # Exact local placement must preserve the stable component identity.
        assert :ok =
                 Controller.place_agent(controller, Ref.ref(:east, :workers), node(), member: 1)

        assert :ok = Controller.await_ready(controller)
        placed = Controller.whereis_agent(controller, Ref.ref(:east, :workers), 1)
        assert node(placed) == node()
        assert Server.agent(placed).state.total == 7
        workers = [placed, List.last(workers)]

        monitor = Process.monitor(bus)
        Process.exit(bus, :kill)
        assert_receive {:DOWN, ^monitor, :process, ^bus, :killed}, 10000
        assert :ok = Controller.reconcile(controller)
        assert :ok = Controller.await_ready(controller)
        replacement = Controller.whereis_bus(controller, :events)
        assert is_pid(replacement) and replacement != bus
        {:ok, second} = Cell.work_signal(%{value: 5})
        assert {:ok, [_]} = Bus.publish(replacement, [second])

        for worker <- workers do
          Observability.await_turn(c.observer, worker, 2)
          snapshot = Server.snapshot(worker)
          assert snapshot.agent.state.total == 12
          assert {:ok, saved, 2} = load_cell(c, snapshot.agent.id)
          assert saved == snapshot.agent
          Observability.assert_turn(c.observer, second, :ok, true, saved.id)
        end

        Observability.assert_topology(c.observer, :repair, 6)
        stop_controller(c, initial.id, [director, replacement | leaders ++ workers])
        assert_empty_agent_pool(c)
        assert JidoTest.RecoverableDeliverySink.attempts(c.jido) == []
      end

      @tag scenario: :bus_recovery
      test "a replaced Bus restores the full Signal journey with trace identity and one Turn per member",
           c do
        initial = topology(c.namespace, 2, true)
        controller = start_controller(c, initial)
        original = members(controller, 2)
        old_bus = Controller.whereis_bus(controller, :work)
        runtime = runtime(controller)

        monitors =
          for pid <- [runtime, old_bus] do
            {pid, Process.monitor(pid)}
          end

        Observability.killed(c.observer, runtime)
        Process.exit(runtime, :kill)

        for {pid, ref} <- monitors do
          assert_receive({:DOWN, ^ref, :process, ^pid, _}, 10000)
        end

        await_new_runtime(c, controller, runtime)
        assert members(controller, 2) == original
        bus = Controller.whereis_bus(controller, :work)
        assert bus != old_bus
        trace = Trace.new_root()

        {:ok, command_signal_1} = Cell.work_signal(%{value: 7})

        {:ok, signal} =
          Trace.put(command_signal_1, trace)

        assert {:ok, [_]} = Bus.publish(bus, [signal])

        ids =
          for agent <- original do
            Observability.await_turn(c.observer, agent, 1)
            assert Server.agent(agent).state == %{label: "cell", received: 1, total: 7}

            snapshot = Server.snapshot(agent)
            assert snapshot.state_version == 1
            assert {:ok, saved, 1} = load_cell(c, snapshot.agent.id)
            assert saved.state == snapshot.agent.state
            saved.id
          end

        Observability.assert_topology(c.observer, :activate, 3)
        stop_controller(c, initial.id, original ++ [bus])

        for id <- ids do
          Observability.assert_turn(c.observer, signal, :ok, true, id)
        end

        events =
          for {_, [:jido, :agent, :turn, :stop], _, meta} <- Observability.events(c.observer),
              meta[:source_signal_id] == signal.id do
            meta
          end

        assert length(events) == 2
        assert Enum.all?(events, &(&1.trace_id == trace.trace_id))
        assert Enum.uniq(Enum.map(events, & &1.turn_id)) |> length() == 2
      end

      @tag :research
      test "an accepted updated target survives Runtime failure and retains ownership", c do
        initial = topology(c.namespace, 1)
        controller = start_controller(c, initial)

        for count <- [2, 3] do
          assert :ok = Controller.update(controller, topology(initial.id, count))
          assert :ok = Controller.await_ready(controller)
        end

        original = members(controller, 3)

        for {pid, value} <- Enum.with_index(original, 1) do
          {:ok, route_signal_1} = Cell.work_signal(%{value: value})

          assert(
            {:ok, _} =
              Jido.AgentServer.call(pid, route_signal_1, [])
          )
        end

        saved = Enum.map(original, &Server.snapshot/1)
        Observability.assert_topology(c.observer, :update, 3)
        old_runtime = runtime(controller)
        monitor = Process.monitor(old_runtime)
        Observability.killed(c.observer, old_runtime)
        Process.exit(old_runtime, :kill)
        assert_receive {:DOWN, ^monitor, :process, ^old_runtime, :killed}, 10000
        await_new_runtime(c, controller, old_runtime)
        status = Controller.status(controller)
        assert status.target_revision == 2
        found = members(controller, 3)
        still_live = Enum.map(original, &Server.snapshot/1)

        # Collect cleanup evidence before asserting the failed membership contract.
        :ok = Supervisor.terminate_child(c.world, {Controller, initial.id})
        orphans = Enum.filter(original, &Process.alive?/1)

        for pid <- orphans do
          stop_agent(c, pid)
        end

        assert {status.agents, found, still_live, orphans} == {3, original, saved, []},
               "SYSTEM-TOPOLOGY-01: Runtime restart lost the accepted target or its owned members. " <>
                 "Observed agents=#{status.agents}, found=#{inspect(found)}, orphan_count=#{length(orphans)}"
      end

      @tag :research
      test "a full Jido restart restores accepted Topology membership as well as member checkpoints",
           c do
        initial = topology(c.namespace, 1)
        controller = start_controller(c, initial)
        target = topology(initial.id, 2)
        assert :ok = Controller.update(controller, target)
        assert :ok = Controller.await_ready(controller)
        added = Controller.whereis_agent(controller, :workers, 2)

        {:ok, route_signal_2} = Cell.work_signal(%{value: 17})

        assert {:ok, committed} =
                 Jido.AgentServer.call(added, route_signal_2, [])

        before = Server.snapshot(added)
        assert {:ok, saved, 1} = load_cell(c, committed.id)
        assert saved.state == committed.state

        services =
          for {_, pid, _, _} <- Supervisor.which_children(c.jido_pid), is_pid(pid) do
            pid
          end

        old = [c.jido_pid | services ++ members(controller, 2)]

        monitors =
          for pid <- old do
            {pid, Process.monitor(pid)}
          end

        controller_monitor = Process.monitor(controller)
        old_runtime = runtime(controller)

        # Hold replacement until the killed tree releases its registered names.
        # This probe isolates durable target recovery from the distinct immediate
        # supervisor-restart race recorded in TODO.md.
        :ok = :sys.suspend(c.world)

        try do
          Process.exit(c.jido_pid, :kill)

          for {pid, ref} <- monitors do
            assert_receive({:DOWN, ^ref, :process, ^pid, _}, 10000)
          end
        after
          :sys.resume(c.world)
        end

        assert_receive {:DOWN, ^controller_monitor, :process, ^controller, _}, 10000

        await_runtime_start(c, old_runtime)

        replacement =
          Enum.find_value(Supervisor.which_children(c.world), fn
            {{Controller, id}, pid, _, _}
            when id == initial.id and is_pid(pid) and pid != controller ->
              pid

            _ ->
              nil
          end)

        assert is_pid(replacement)

        assert :ok = Controller.await_ready(replacement)
        actual_count = Controller.status(replacement).agents
        assert Controller.status(replacement).target_revision == 1
        recovered_member = Controller.whereis_agent(replacement, :workers, 2)
        assert {:ok, still_saved, 1} = load_cell(c, committed.id)
        assert still_saved.state == committed.state

        # Control experiment: resubmitting the missing target must recover its
        # Agent checkpoint. This separates target loss from adapter state loss.
        assert :ok = Controller.update(replacement, target)
        assert :ok = Controller.await_ready(replacement)
        restored = Controller.whereis_agent(replacement, :workers, 2)
        assert Server.snapshot(restored).agent.state == before.agent.state
        assert Server.snapshot(restored).state_version == before.state_version
        stop_controller(c, initial.id, members(replacement, 2))

        assert actual_count == 2 and is_pid(recovered_member),
               "SYSTEM-TOPOLOGY-02: the Agent checkpoint survived, but the accepted Topology target did not. " <>
                 "Restored count=#{actual_count}; added member=#{inspect(recovered_member)}"
      end

      defp topology(id, count, bus? \\ false) do
        attrs =
          %{name: "system_topology", groups: [%{key: :workers, module: Cell, count: count}]}

        attrs =
          if bus?,
            do:
              Map.update(
                Map.update(
                  attrs,
                  :resources,
                  [%{key: :work, kind: :bus}],
                  &(&1 ++ [%{key: :work, kind: :bus}])
                ),
                :connections,
                [%{agent: :workers, to: :work, path: "examples.topology.cell.work"}],
                &(&1 ++ [%{agent: :workers, to: :work, path: "examples.topology.cell.work"}])
              ),
            else: attrs

        Jido.Topology.unwrap!(
          with {:ok, definition} <-
                 Jido.Topology.new(Map.put(attrs, :startup, retry_interval: 10)) do
            Jido.Topology.instantiate(definition, id: id)
          end
        )
      end

      defp start_controller(c, topology) do
        {:ok, controller} =
          Supervisor.start_child(
            c.world,
            {Controller, jido: c.jido, topology: topology, repair: :manual}
          )

        assert :ok = Controller.await_ready(controller)
        controller
      end

      defp stop_controller(c, id, pids) do
        monitors = for pid <- pids, do: {pid, Process.monitor(pid)}
        :ok = Supervisor.terminate_child(c.world, {Controller, id})
        for {pid, ref} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 10_000)
      end

      defp members(controller, count),
        do: Enum.map(1..count, &Controller.whereis_agent(controller, :workers, &1))

      defp runtime(controller),
        do:
          Enum.find_value(Supervisor.which_children(controller), fn
            {Runtime, pid, _, _} when is_pid(pid) -> pid
            _ -> nil
          end)

      defp await_runtime_start(c, previous) do
        Observability.await(c.observer, fn
          {pid, [:jido, :topology, :operation, :start], _, %{topology_operation: :activate}} ->
            pid != previous

          _ ->
            false
        end)
      end

      defp await_new_runtime(c, controller, previous) do
        await_runtime_start(c, previous)

        try do
          assert :ok = Controller.await_ready(controller)
        catch
          :exit, reason ->
            flunk(
              "Controller readiness failed: #{inspect(reason)}\n" <>
                "Status: #{inspect(Controller.status(controller))}"
            )
        end
      end

      defp load_cell(c, id),
        do:
          Jido.Persistence.load_agent_with_revision(c.store, Cell, id,
            instance: c.jido,
            namespace: c.namespace
          )
    end
  end
end
