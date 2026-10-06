defmodule Jido.Topology.ControllerTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.{Cell, Hierarchy, Independent, Swarm}
  alias Jido.Signal.Bus
  alias Jido.Topology.Controller
  alias Jido.Topology.BusInputs

  defmodule LifecycleControl do
    use Jido.Agent, name: "topology_lifecycle_control"

    agent do
      schema Zoi.object(%{events: Zoi.list(Zoi.string()) |> Zoi.default([])})
    end

    routes do
      route "jido.topology.lifecycle.**" do
        action _input, context: context do
          {:ok,
           %{
             context.agent_state
             | events: context.agent_state.events ++ [context.signal.type]
           }}
        end
      end
    end
  end

  test "invalid repair policy fails before topology activation", %{jido: jido} do
    assert {:error, %Jido.Error.ValidationError{}} =
             Controller.start_link(
               jido: jido,
               topology: Independent.new!(id: "invalid-repair"),
               repair: :sometimes
             )

    assert Jido.agent_count(jido) == 0
  end

  test "sends lifecycle Signals to a normal control Agent route", %{jido: jido} do
    assert Jido.Topology.Signal.types() == [
             "jido.topology.lifecycle.operation.started",
             "jido.topology.lifecycle.operation.completed",
             "jido.topology.lifecycle.component.ready",
             "jido.topology.lifecycle.component.failed",
             "jido.topology.lifecycle.status.changed"
           ]

    {:ok, control} = Jido.start_agent(jido, LifecycleControl, id: "topology-control")

    controller =
      start_supervised!(
        {Controller,
         jido: jido,
         topology: Independent.new!(id: "lifecycle-signals"),
         lifecycle: control,
         repair: :manual}
      )

    assert :ok = Controller.await_ready(controller)

    eventually(fn ->
      events = Server.agent(control).state.events

      "jido.topology.lifecycle.operation.started" in events and
        "jido.topology.lifecycle.component.ready" in events and
        "jido.topology.lifecycle.operation.completed" in events and
        "jido.topology.lifecycle.status.changed" in events
    end)
  end

  test "validates the optional lifecycle target before activation", %{jido: jido} do
    assert {:error, %Jido.Error.ValidationError{}} =
             Controller.start_link(
               jido: jido,
               topology: Independent.new!(id: "invalid-lifecycle"),
               lifecycle: :not_an_agent
             )

    assert Jido.agent_count(jido) == 0
  end

  test "starts independent agents, preserves committed state, and cleans up", %{jido: jido} do
    controller =
      start_supervised!({Controller, jido: jido, topology: Independent.new!(id: "independent")})

    assert :ok = Controller.await_ready(controller)
    left = Controller.whereis_agent(controller, :left)
    right = Controller.whereis_agent(controller, :right)
    assert Server.agent(left).state.label == "left"
    assert Server.agent(right).state.label == "right"

    {:ok, route_signal_1} = Cell.work_signal(%{value: 3})

    assert {:ok, _} =
             Jido.AgentServer.call(left, route_signal_1, [])

    assert {:error, {:already_started, ^controller}} =
             Controller.start_link(jido: jido, topology: Independent.new!(id: "independent"))

    assert Server.agent(left).state.total == 3
    Supervisor.stop(controller)
    eventually(fn -> not Process.alive?(left) and not Process.alive?(right) end)
  end

  test "public readiness follows a blocked Bus client reconnect", %{jido: jido} do
    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(%{
                 name: "live_bus_readiness",
                 resources: [%{key: :events, kind: :bus}],
                 agents: [%{key: :cell, module: Cell}],
                 connections: [%{agent: :cell, to: :events, path: "examples.topology.cell.work"}]
               }) do
          Jido.Topology.instantiate(definition, id: unique_id("live-bus"))
        end
      )

    controller =
      start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})

    assert :ok = Controller.await_ready(controller)
    bus = Controller.whereis_bus(controller, :events)
    agent = Controller.whereis_agent(controller, :cell)
    %{pid: inputs} = Server.children(agent)[{:plugin, BusInputs}]
    [{_, client, _, _}] = Supervisor.which_children(inputs)
    %{subscription_id: subscription_id, bus_ref: bus_ref} = :sys.get_state(client)
    assert :ok = Bus.unsubscribe(bus, subscription_id)
    Process.demonitor(bus_ref, [:flush])

    token = make_ref()

    :sys.replace_state(client, fn state ->
      %{state | bus: nil, bus_ref: nil, subscription_id: nil, reconnect_token: token}
    end)

    assert :ok = :sys.suspend(bus)

    try do
      send(client, {:reconnect, token})
      assert Process.alive?(bus)
      assert Process.alive?(agent)

      assert %{status: :degraded, errors: %{"agent/cell" => :subscription_unavailable}} =
               Controller.status(controller, 500)

      assert catch_exit(Controller.await_ready(controller, 200))
    after
      assert :ok = :sys.resume(bus)
    end

    assert :ok = Controller.await_ready(controller, 2_000)
    assert %{status: :ready, errors: %{}} = Controller.status(controller)
    assert Controller.whereis_agent(controller, :cell) == agent
  end

  test "public readiness follows a lost live parent binding", %{jido: jido} do
    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(%{
                 name: "live_parent_readiness",
                 agents: [%{key: :parent, module: Cell}, %{key: :child, module: Cell}],
                 relationships: [%{parent: :parent, child: :child}]
               }) do
          Jido.Topology.instantiate(definition, id: unique_id("live-parent"))
        end
      )

    controller =
      start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})

    assert :ok = Controller.await_ready(controller)
    parent = Controller.whereis_agent(controller, :parent)
    child = Controller.whereis_agent(controller, :child)
    {:idle, original} = :sys.get_state(parent)
    assert Server.children(parent)["agent/child"].pid == child

    :sys.replace_state(parent, fn {phase, data} ->
      {phase, %{data | children: Map.delete(data.children, "agent/child")}}
    end)

    assert Process.alive?(parent)
    assert Process.alive?(child)

    assert %{status: :degraded, errors: %{"agent/child" => :parent_binding_pending}} =
             Controller.status(controller)

    :sys.replace_state(parent, fn {phase, _data} -> {phase, original} end)
    assert %{status: :ready, errors: %{}} = Controller.status(controller)
  end

  test "activation, repair, and cleanup emit bounded local topology spans", %{jido: jido} do
    instance = Independent.new!(id: "observed-topology")
    handler = {__MODULE__, make_ref()}

    events =
      for ending <- [:start, :stop, :exception],
          do: [:jido, :topology, :operation, ending]

    :ok =
      :telemetry.attach_many(
        handler,
        events,
        fn event, measurements, metadata, owner ->
          send(owner, {:topology_event, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    controller =
      start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})

    assert :ok = Controller.await_ready(controller)
    assert :ok = Controller.reconcile(controller)
    assert :ok = Controller.await_ready(controller)
    assert :ok = Supervisor.stop(controller)

    observed = collect_topology_events([])
    starts = Enum.filter(observed, &(elem(&1, 0) == :start))
    stops = Enum.filter(observed, &(elem(&1, 0) == :stop))

    assert Enum.map(starts, fn {_ending, metadata, _measurements} ->
             metadata.topology_operation
           end) == [:activate, :repair, :cleanup]

    assert Enum.map(stops, fn {_ending, metadata, _measurements} ->
             {metadata.topology_operation, metadata.status}
           end) == [{:activate, :ok}, {:repair, :ok}, {:cleanup, :ok}]

    for {_ending, metadata, measurements} <- observed do
      assert metadata.schema_version == 1
      assert metadata.topology_id == instance.id
      refute Map.has_key?(metadata, :jido_instance)
      refute Map.has_key?(metadata, :components)
      refute Map.has_key?(metadata, :errors)
      assert measurements.component_count == 2
      assert is_integer(measurements.ready_count)
      assert is_integer(measurements.failed_count)
    end

    assert List.last(stops) |> elem(2) |> Map.fetch!(:ready_count) == 0
  end

  defp collect_topology_events(acc) do
    receive do
      {:topology_event, event, measurements, metadata} ->
        collect_topology_events([{List.last(event), metadata, measurements} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "establishes logical ownership for nested groups", %{jido: jido} do
    controller = start_supervised!({Controller, jido: jido, topology: Hierarchy.new!(id: "tree")})
    assert :ok = Controller.await_ready(controller)
    coordinator = Controller.whereis_agent(controller, :coordinator)
    leader = Controller.whereis_agent(controller, :leader)
    assert Server.children(coordinator)["agent/leader"].pid == leader
    assert map_size(Server.children(leader)) == 3
    worker = Controller.whereis_agent(controller, :workers, "1")

    assert {:ok, %{parent_id: "tree/agent/leader"}} =
             Jido.agent_parent_binding(jido, Server.agent(worker).id)
  end

  test "normalizes group member lookup and rejects unsupported values", %{jido: jido} do
    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(%{
                 name: "member-lookup",
                 groups: [
                   %{key: :counted, module: Cell, count: 1},
                   %{key: :keyed, module: Cell, members: [%{id: :alpha}], key_by: :id}
                 ]
               }) do
          Jido.Topology.instantiate(definition, id: "member-lookup")
        end
      )

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)
    assert Controller.whereis_agent(controller, :counted, 1)

    assert Controller.whereis_agent(controller, :counted, 1) ==
             Controller.whereis_agent(controller, :counted, "1")

    assert Controller.whereis_agent(controller, :keyed, :alpha) ==
             Controller.whereis_agent(controller, :keyed, "alpha")

    for member <- [0, -1, %{}, self(), true, false, "", String.duplicate("x", 256)] do
      assert Controller.whereis_agent(controller, :keyed, member) == nil
    end

    assert Process.alive?(controller)
  end

  test "broadcasts each Signal to every member", %{jido: jido} do
    instance = Swarm.new!(id: "swarm", input: %{worker_count: 4})
    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)
    bus = Controller.whereis_bus(controller, :work)

    {:ok, command_signal_1} = Cell.work_signal(%{value: 7})

    assert {:ok, [_]} =
             Bus.publish(bus, [command_signal_1])

    for index <- 1..4 do
      worker = Controller.whereis_agent(controller, :workers, index)
      eventually(fn -> Server.agent(worker).state.total == 7 end)
    end

    assert %{status: :ready, agents: 5, resources: 1, errors: %{}} = Controller.status(controller)
  end

  test "supports more than one Bus subscription on an Agent", %{jido: jido} do
    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(%{
                 name: "multiple",
                 agents: [%{key: :cell, module: Cell}],
                 resources: [%{key: :a, kind: :bus}, %{key: :b, kind: :bus}],
                 connections: [
                   %{agent: :cell, to: :a, path: "examples.topology.cell.work"},
                   %{agent: :cell, to: :b, path: "examples.topology.cell.work"}
                 ]
               }) do
          Jido.Topology.instantiate(definition, id: "multiple")
        end
      )

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)

    for key <- [:a, :b] do
      {:ok, command_signal_2} = Cell.work_signal(%{value: 2})

      assert(
        {:ok, [_]} =
          Bus.publish(Controller.whereis_bus(controller, key), [command_signal_2])
      )
    end

    agent = Controller.whereis_agent(controller, :cell)
    eventually(fn -> Server.agent(agent).state.total == 4 end)
  end

  test "repair leaves an explicitly stopped Agent stopped", %{jido: jido} do
    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(Map.put(Independent.topology(), :startup, retry_interval: 10)) do
          Jido.Topology.instantiate(definition, id: "repair")
        end
      )

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)
    old = Controller.whereis_agent(controller, :left)
    :ok = Jido.stop_agent(jido, old)

    assert :ok = Controller.reconcile(controller)
    eventually(fn -> Controller.status(controller).active == 0 end)
    assert Controller.whereis_agent(controller, :left) == nil
    assert Controller.status(controller).errors["agent/left"] == :member_stopped
  end

  test "repairs parent bindings after parent failure", %{jido: jido} do
    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(
                 Hierarchy.topology()
                 |> Map.put(:startup, retry_interval: 10)
                 |> Map.update!(:relationships, fn relationships ->
                   Enum.map(relationships, &Map.put(&1, :on_parent_exit, :continue))
                 end)
               ) do
          Jido.Topology.instantiate(definition, id: "repair-tree")
        end
      )

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)
    old = Controller.whereis_agent(controller, :leader)
    Process.exit(old, :kill)

    eventually(
      fn ->
        new = Controller.whereis_agent(controller, :leader)
        is_pid(new) and new != old and map_size(Server.children(new)) == 3
      end,
      timeout: 5_000
    )
  end

  test "reports identity conflicts and never stops an unrelated agent", %{jido: jido} do
    {:ok, existing} = Jido.start_agent(jido, Cell, id: "conflict/agent/left")

    controller =
      start_supervised!({Controller, jido: jido, topology: Independent.new!(id: "conflict")})

    eventually(fn ->
      Controller.status(controller).errors["agent/left"] == :agent_identity_in_use
    end)

    assert Controller.whereis_agent(controller, :left) == nil
    Supervisor.stop(controller)
    assert Process.alive?(existing)
  end

  test "does not return a Bus that activation rejected", %{jido: jido} do
    existing = start_supervised!({Bus, name: "bus-conflict/bus/work", jido: jido})

    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(%{name: "bus-conflict", resources: [%{key: :work, kind: :bus}]}) do
          Jido.Topology.instantiate(definition, id: "bus-conflict")
        end
      )

    controller = start_supervised!({Controller, jido: jido, topology: instance})

    eventually(fn ->
      Controller.status(controller).errors["bus/work"] == :bus_identity_in_use
    end)

    assert Controller.whereis_bus(controller, :work) == nil
    Supervisor.stop(controller)
    assert Process.alive?(existing)
  end

  test "looks up a ready Bus without scanning the resource supervisor", %{jido: jido} do
    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(%{
                 name: "cached-bus-lookup",
                 resources: [%{key: :work, kind: :bus}]
               }) do
          Jido.Topology.instantiate(definition, id: "cached-bus-lookup")
        end
      )

    controller =
      start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})

    assert :ok = Controller.await_ready(controller)
    bus = Controller.whereis_bus(controller, :work)
    resources = Controller.name(jido, instance.id, :resources)
    :ok = :sys.suspend(resources)

    try do
      lookup = Task.async(fn -> Controller.whereis_bus(controller, :work) end)
      result = Task.yield(lookup, 500) || Task.shutdown(lookup, :brutal_kill)

      assert result == {:ok, bus}
    after
      :ok = :sys.resume(resources)
    end
  end

  test "readiness can succeed after an earlier caller times out", %{jido: jido} do
    {:ok, existing} = Jido.start_agent(jido, Cell, id: "waiting/agent/left")

    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(Map.put(Independent.topology(), :startup, retry_interval: 10)) do
          Jido.Topology.instantiate(definition, id: "waiting")
        end
      )

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    eventually(fn -> Controller.status(controller).status == :degraded end)
    assert catch_exit(Controller.await_ready(controller, 10))
    :ok = Jido.stop_agent(jido, existing)
    assert :ok = Controller.await_ready(controller, 2_000)
  end

  test "scopes Buses and agents to the topology instance", %{jido: jido} do
    controllers =
      for id <- ["one", "two"] do
        controller =
          start_supervised!(
            {Controller, jido: jido, topology: Swarm.new!(id: id, input: %{worker_count: 1})}
          )

        assert :ok = Controller.await_ready(controller)
        controller
      end

    [first, second] = controllers
    assert Controller.whereis_bus(first, :work) != Controller.whereis_bus(second, :work)

    assert Controller.whereis_agent(first, :workers, 1) !=
             Controller.whereis_agent(second, :workers, 1)
  end

  defmodule PersistentJido do
    use Jido,
      otp_app: :jido,
      namespace: "controller-test",
      persistence: {Jido.Persistence.ETS, table: __MODULE__}
  end

  defmodule PreparationAdapter do
    @behaviour Jido.Persistence.Adapter

    def validate_options(opts), do: Jido.Persistence.ETS.validate_options(opts)

    def get(key, opts) do
      case Elixir.Agent.get(Keyword.fetch!(opts, :control), & &1) do
        :ok -> Jido.Persistence.ETS.get(key, opts)
        {:error, reason} -> {:error, reason}
      end
    end

    defdelegate put(key, value, opts), to: Jido.Persistence.ETS
    defdelegate compare_and_swap(key, expected, value, opts), to: Jido.Persistence.ETS
    defdelegate delete(key, opts), to: Jido.Persistence.ETS
  end

  test "prepares durable checkpoint definitions without accepting or starting the member" do
    control = start_supervised!({Elixir.Agent, fn -> :ok end})
    jido = unique_instance("definition-preparation")

    start_supervised!(
      {Jido,
       name: jido,
       namespace: "controller-test/#{jido}",
       persistence: {PreparationAdapter, table: jido, control: control}},
      id: jido
    )

    id = unique_id("definition-preparation")
    start_supervised!({Jido.Topology.Runtime, empty_runtime(jido, id)})
    source = JidoTest.AgentFixtures.CounterAgent.definition()
    compatible = %{source | description: "compatible candidate"}

    assert :ok =
             Jido.Topology.Runtime.add_agent(jido, id, :actor, source,
               initial_state: %{count: 7, history: []}
             )

    assert :ok = Jido.Topology.Runtime.activate(jido, id, :actor)
    assert :ok = Jido.Topology.Runtime.await_ready(jido, id)
    assert :ok = Jido.Topology.Runtime.remove_agent(jido, id, :actor)
    assert Jido.agent_count(jido) == 0

    assert :ok =
             Jido.Topology.Runtime.prepare_agent_definition(
               jido,
               id,
               :actor,
               source,
               compatible,
               :preserve,
               initial_state: %{count: 2, history: []}
             )

    assert Jido.Topology.Runtime.target(jido, id).definition.agents == []
    assert Jido.Topology.Runtime.whereis_member(jido, id, :actor) == nil

    physical_id = id <> "/agent/actor"

    assert {:ok, saved, 0} =
             Jido.Persistence.load_agent_with_revision(jido, source.module, physical_id)

    assert saved.state == %{count: 7, history: []}

    incompatible = %{
      source
      | schema:
          Zoi.object(%{
            count: Zoi.string() |> Zoi.default("zero"),
            history: Zoi.list(Zoi.string()) |> Zoi.default([])
          })
    }

    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.Topology.Runtime.prepare_agent_definition(
               jido,
               id,
               :actor,
               source,
               incompatible,
               :preserve,
               initial_state: %{count: "reset", history: []}
             )

    assert {:ok, unchanged, 0} =
             Jido.Persistence.load_agent_with_revision(jido, source.module, physical_id)

    assert unchanged == saved

    candidate = %{source | description: "reset candidate"}
    initial_state = %{count: 2, history: []}

    tasks =
      for _index <- 1..2 do
        Task.async(fn ->
          Jido.Topology.Runtime.prepare_agent_definition(
            jido,
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

    assert {:ok, prepared, 1} =
             Jido.Persistence.load_agent_with_revision(jido, source.module, physical_id)

    assert prepared.state == initial_state
    assert prepared.description == "reset candidate"

    key =
      Jido.Persistence.agent_key(
        Jido.Agent.Ref.new!(namespace: "controller-test/#{jido}", id: physical_id)
      )

    assert {:ok, bytes_before} = Jido.Persistence.ETS.get(key, table: jido, control: control)

    assert :ok =
             Jido.Topology.Runtime.prepare_agent_definition(
               jido,
               id,
               :actor,
               source,
               candidate,
               :reset,
               initial_state: initial_state
             )

    assert {:ok, ^bytes_before} = Jido.Persistence.ETS.get(key, table: jido, control: control)
    assert %{kind: :active, revision: 1} = :erlang.binary_to_term(bytes_before, [:safe])
    assert Jido.agent_count(jido) == 0
  end

  test "preserve activation writes the current definition before immediate Hibernate" do
    control = start_supervised!({Elixir.Agent, fn -> :ok end})
    jido = unique_instance("preserve-hibernate")

    start_supervised!(
      {Jido,
       name: jido,
       namespace: "controller-test/#{jido}",
       persistence: {PreparationAdapter, table: jido, control: control}},
      id: jido
    )

    id = unique_id("preserve-hibernate")
    start_supervised!({Jido.Topology.Runtime, empty_runtime(jido, id)})
    source = JidoTest.AgentFixtures.CounterAgent.definition()
    candidate = %{source | description: "preserved candidate"}
    initial_state = %{count: 7, history: []}

    assert :ok =
             Jido.Topology.Runtime.add_agent(jido, id, :actor, source,
               initial_state: initial_state
             )

    assert :ok = Jido.Topology.Runtime.activate(jido, id, :actor)
    assert :ok = Jido.Topology.Runtime.await_ready(jido, id)
    assert :ok = Jido.Topology.Runtime.remove_agent(jido, id, :actor)

    assert :ok =
             Jido.Topology.Runtime.prepare_agent_definition(
               jido,
               id,
               :actor,
               source,
               candidate,
               :preserve,
               initial_state: %{count: 0, history: []}
             )

    assert :ok =
             Jido.Topology.Runtime.add_agent(jido, id, :actor, candidate,
               initial_state: %{count: 0, history: []}
             )

    assert :ok = Jido.Topology.Runtime.activate(jido, id, :actor)
    assert :ok = Jido.Topology.Runtime.await_ready(jido, id)
    member = Jido.Topology.Runtime.whereis_member(jido, id, :actor)

    assert %{agent: %{description: "preserved candidate"}, state_version: 1} =
             Server.snapshot(member)

    assert :ok = Jido.Topology.Runtime.hibernate(jido, id, :actor)

    physical_id = id <> "/agent/actor"

    assert {:ok, persisted, 1} =
             Jido.Persistence.load_agent_with_revision(jido, source.module, physical_id)

    assert persisted.description == "preserved candidate"
    assert persisted.state == initial_state

    assert :ok = Jido.Topology.Runtime.thaw(jido, id, :actor)
    restored = Jido.Topology.Runtime.whereis_member(jido, id, :actor)
    assert Server.snapshot(restored).state_version == 1
  end

  test "definition preparation accepts a missing checkpoint and reports storage read failure" do
    control = start_supervised!({Elixir.Agent, fn -> :ok end})
    jido = unique_instance("definition-read")

    start_supervised!(
      {Jido,
       name: jido,
       namespace: "controller-test/#{jido}",
       persistence: {PreparationAdapter, table: jido, control: control}},
      id: jido
    )

    id = unique_id("definition-read")
    start_supervised!({Jido.Topology.Runtime, empty_runtime(jido, id)})
    source = JidoTest.AgentFixtures.CounterAgent.definition()
    candidate = %{source | description: "candidate"}

    assert :ok =
             Jido.Topology.Runtime.prepare_agent_definition(
               jido,
               id,
               :missing,
               source,
               candidate,
               :preserve,
               initial_state: %{count: 0, history: []}
             )

    physical_id = id <> "/agent/missing"

    assert {:error, :not_found} =
             Jido.Persistence.load_agent(jido, source.module, physical_id)

    assert :ok =
             Jido.Topology.Runtime.prepare_agent_definition(
               jido,
               id,
               :missing,
               source,
               candidate,
               :reset,
               initial_state: %{count: 3, history: []}
             )

    assert {:ok, %{state: %{count: 3}}, 0} =
             Jido.Persistence.load_agent_with_revision(jido, source.module, physical_id)

    Elixir.Agent.update(control, fn _ -> {:error, :storage_unavailable} end)

    assert {:error, :storage_unavailable} =
             Jido.Topology.Runtime.prepare_agent_definition(
               jido,
               id,
               :other,
               source,
               candidate,
               :preserve,
               initial_state: %{count: 0, history: []}
             )
  end

  test "definition preparation rejects unsupported policy, module changes, and writer state", %{
    jido: jido
  } do
    id = unique_id("definition-guards")
    start_supervised!({Jido.Topology.Runtime, empty_runtime(jido, id)})
    source = JidoTest.AgentFixtures.CounterAgent.definition()
    candidate = %{source | description: "candidate"}
    other = LifecycleControl.definition()
    opts = [initial_state: %{count: 0, history: []}]

    assert {:error, {:unsupported_definition_policy, :migrate}} =
             Jido.Topology.Runtime.prepare_agent_definition(
               jido,
               id,
               :actor,
               source,
               candidate,
               :migrate,
               opts
             )

    assert {:error, {:agent_module_mismatch, _, _}} =
             Jido.Topology.Runtime.prepare_agent_definition(
               jido,
               id,
               :actor,
               source,
               other,
               :preserve,
               initial_state: %{events: []}
             )

    for forbidden <- [[revision: 1], [partition: "private"], [checkpoint: <<1, 2, 3>>]] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Jido.Topology.Runtime.prepare_agent_definition(
                 jido,
                 id,
                 :actor,
                 source,
                 candidate,
                 :preserve,
                 forbidden
               )
    end

    assert :ok = Jido.Topology.Runtime.add_agent(jido, id, :actor, source, opts)

    assert {:error, {:definition_preparation_rejected, :accepted}} =
             Jido.Topology.Runtime.prepare_agent_definition(
               jido,
               id,
               :actor,
               source,
               candidate,
               :preserve,
               opts
             )

    assert :ok = Jido.Topology.Runtime.activate(jido, id, :actor)
    assert :ok = Jido.Topology.Runtime.await_ready(jido, id)
    active = Jido.Topology.Runtime.whereis_member(jido, id, :actor)

    assert {:error, {:definition_preparation_rejected, :accepted}} =
             Jido.Topology.Runtime.prepare_agent_definition(
               jido,
               id,
               :actor,
               source,
               candidate,
               :reset,
               opts
             )

    assert Process.alive?(active)
  end

  test "definition preparation rejects selected, ready, repair, stopped-child, and live state", %{
    jido: jido
  } do
    source = JidoTest.AgentFixtures.CounterAgent.definition()
    candidate = %{source | description: "candidate"}
    opts = [initial_state: %{count: 0, history: []}]

    for {field, value, reason} <- [
          {:selected, MapSet.new(["agent/actor"]), :selected},
          {:ready, %{"agent/actor" => self()}, :ready},
          {:pending, MapSet.new(["agent/actor"]), :starting},
          {:active, %{make_ref() => :repair_job}, :repair_active}
        ] do
      id = unique_id("definition-#{field}")
      start_supervised!({Jido.Topology.Runtime, empty_runtime(jido, id)}, id: {field, id})
      runtime = Jido.Topology.Runtime.controller(jido, id) |> controller_runtime()
      original = :sys.get_state(runtime)
      :sys.replace_state(runtime, &Map.put(&1, field, value))

      assert {:error, {:definition_preparation_rejected, ^reason}} =
               Jido.Topology.Runtime.prepare_agent_definition(
                 jido,
                 id,
                 :actor,
                 source,
                 candidate,
                 :preserve,
                 opts
               )

      :sys.replace_state(runtime, fn _ -> original end)
    end

    stopped_id = unique_id("definition-stopped")
    start_supervised!({Jido.Topology.Runtime, empty_runtime(jido, stopped_id)})
    agents = Controller.name(jido, stopped_id, :agents)
    test_pid = self()

    assert {:ok, child} =
             Supervisor.start_child(agents, %{
               id: "agent/actor",
               start:
                 {Task, :start_link,
                  [
                    fn ->
                      send(test_pid, {:temporary_child_started, self()})

                      receive do
                        :stop -> :ok
                      end
                    end
                  ]},
               restart: :transient
             })

    assert_receive {:temporary_child_started, ^child}
    monitor = Process.monitor(child)
    send(child, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^child, :normal}

    assert {:error, {:definition_preparation_rejected, :stopped_child}} =
             Jido.Topology.Runtime.prepare_agent_definition(
               jido,
               stopped_id,
               :actor,
               source,
               candidate,
               :preserve,
               opts
             )

    live_id = unique_id("definition-live")
    start_supervised!({Jido.Topology.Runtime, empty_runtime(jido, live_id)})
    physical_id = live_id <> "/agent/actor"

    {:ok, live} =
      Jido.start_agent(jido, source, id: physical_id, initial_state: opts[:initial_state])

    assert {:error, {:definition_preparation_rejected, :live_process}} =
             Jido.Topology.Runtime.prepare_agent_definition(
               jido,
               live_id,
               :actor,
               source,
               candidate,
               :preserve,
               opts
             )

    assert Process.alive?(live)
  end

  test "restores committed state and Bus subscriptions after controller shutdown" do
    start_supervised!(PersistentJido)
    id = unique_id("persistent-topology")

    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(Map.put(Swarm.topology(), :startup, retry_interval: 10)) do
          Jido.Topology.instantiate(definition, id: id, input: %{worker_count: 2})
        end
      )

    controller = start_supervised!({Controller, jido: PersistentJido, topology: instance})
    assert :ok = Controller.await_ready(controller, 5000)

    {:ok, route_signal_2} = Cell.work_signal(%{value: 12})

    assert {:ok, _} =
             Jido.AgentServer.call(
               Controller.whereis_agent(controller, :workers, 1),
               route_signal_2,
               []
             )

    stop_supervised!({Controller, id})
    controller = start_supervised!({Controller, jido: PersistentJido, topology: instance})
    assert :ok = Controller.await_ready(controller, 5000)
    worker = Controller.whereis_agent(controller, :workers, 1)
    assert Server.agent(worker).state.total == 12

    {:ok, command_signal_3} = Cell.work_signal(%{value: 5})

    assert {:ok, [_]} =
             Bus.publish(Controller.whereis_bus(controller, :work), [command_signal_3])

    eventually(fn -> Server.agent(worker).state.total == 17 end)
    Process.exit(worker, :kill)

    eventually(
      fn ->
        current = Controller.whereis_agent(controller, :workers, 1)
        is_pid(current) and current != worker and Server.agent(current).state.total == 17
      end,
      timeout: 5000
    )

    assert :ok = Controller.await_ready(controller, 5000)
  end

  defp empty_runtime(jido, id) do
    [
      jido: jido,
      id: id,
      topology: Jido.Topology.new!(name: "definition_preparation"),
      activation: :lazy,
      repair: :manual
    ]
  end

  defp unique_instance(prefix),
    do: String.to_atom(unique_id(prefix))

  defp controller_runtime(controller) do
    Enum.find_value(Supervisor.which_children(controller), fn
      {Jido.Topology.Controller.Runtime, pid, _, _} -> pid
      _other -> nil
    end)
  end

  test "repairs a Bus and its subscriptions after a Bus failure", %{jido: jido} do
    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(Map.put(Swarm.topology(), :startup, retry_interval: 10)) do
          Jido.Topology.instantiate(definition, id: "bus-repair", input: %{worker_count: 2})
        end
      )

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)
    bus = Controller.whereis_bus(controller, :work)
    Process.exit(bus, :kill)

    eventually(
      fn ->
        current = Controller.whereis_bus(controller, :work)
        is_pid(current) and current != bus and Controller.status(controller).status == :ready
      end,
      timeout: 5000
    )

    {:ok, command_signal_4} = Cell.work_signal(%{value: 5})

    assert {:ok, [_]} =
             Bus.publish(Controller.whereis_bus(controller, :work), [command_signal_4])

    eventually(fn ->
      Server.agent(Controller.whereis_agent(controller, :workers, 1)).state.total == 5
    end)
  end

  test "a controller worker crash retains owned agents and their state", %{jido: jido} do
    instance = Independent.new!(id: "controller-repair")
    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)
    left = Controller.whereis_agent(controller, :left)

    {:ok, route_signal_3} = Cell.work_signal(%{value: 9})

    assert {:ok, _} =
             Jido.AgentServer.call(left, route_signal_3, [])

    {_, runtime, _, _} =
      Enum.find(
        Supervisor.which_children(controller),
        &(elem(&1, 0) == Jido.Topology.Controller.Runtime)
      )

    :ok = GenServer.stop(runtime, :worker_crash)

    eventually(fn ->
      case Enum.find(
             Supervisor.which_children(controller),
             &(elem(&1, 0) == Jido.Topology.Controller.Runtime)
           ) do
        {_, pid, _, _} when is_pid(pid) -> pid != runtime
        _ -> false
      end
    end)

    assert :ok = Controller.await_ready(controller)
    assert Controller.whereis_agent(controller, :left) == left
    assert Server.agent(left).state.total == 9
  end
end
