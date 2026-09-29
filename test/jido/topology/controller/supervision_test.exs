defmodule Jido.Topology.Controller.SupervisionTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Topology.{BusInputs, Controller}
  alias JidoTest.SupervisedCounter, as: Counter

  defmodule OtherCounter do
    use Jido.Agent, name: "other_supervised_counter"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
      plugin Counter.Runtime, config: [label: "current"]
    end
  end

  test "readiness rejects a live member whose module no longer matches the target", c do
    {controller, _instance} = start_topology(c.jido)
    server = Controller.whereis_agent(controller, :counter)
    assert {:ok, _} = Server.upgrade(server, OtherCounter, &{:ok, &1.state})
    assert Process.alive?(server)
    assert Controller.whereis_agent(controller, :counter) == nil

    assert %{status: :degraded, errors: %{"agent/counter" => :agent_identity_in_use}} =
             Controller.status(controller)

    assert {:ok, _} = Server.upgrade(server, Counter, &{:ok, &1.state})
    assert :ok = Controller.await_ready(controller, 1_000)
    assert Controller.whereis_agent(controller, :counter) == server
  end

  for mode <- [:current, :replacement] do
    test "status stays bounded when a #{mode} member cannot answer an identity check", c do
      {controller, instance} = start_topology(c.jido)
      original = Controller.whereis_agent(controller, :counter)

      server =
        if unquote(mode) == :replacement do
          kill(original)
          id = instance.plan.agents["agent/counter"].id
          eventually(fn -> is_pid(Jido.whereis_agent(c.jido, id)) end)
          Jido.whereis_agent(c.jido, id)
        else
          original
        end

      :ok = :sys.suspend(server)

      try do
        assert %{status: :degraded, errors: %{"agent/counter" => :member_unavailable}} =
                 Controller.status(controller, 1_000)
      after
        :ok = :sys.resume(server)
      end

      assert :ok = Controller.await_ready(controller, 1_000)
    end
  end

  test "OTP restores committed state and runtime inputs while the coordinator is paused", c do
    {controller, instance} = start_topology(c.jido)
    server = Controller.whereis_agent(controller, :counter)

    assert {"agent/counter", ^server, :worker, [Server]} =
             List.keyfind(
               Supervisor.which_children(Controller.name(c.jido, instance.id, :agents)),
               "agent/counter",
               0
             )

    {:ok, increment} = Counter.increment_signal(%{})
    {:ok, reject} = Counter.reject_signal(%{})
    assert {:ok, committed} = Server.call(server, increment)
    assert {:error, _} = Server.call(server, reject)
    snapshot = Server.snapshot(server)
    plugin = Server.children(server)[{:plugin, Counter.Runtime}]
    plugin_ref = Process.monitor(plugin.pid)
    wrapper_ref = Process.monitor(plugin.lifecycle_pid)
    coordinator = child(controller, Controller.Runtime)
    :ok = :sys.suspend(coordinator)

    try do
      kill(server)
      id = instance.plan.agents["agent/counter"].id
      eventually(fn -> is_pid(Jido.whereis_agent(c.jido, id)) end)
      replacement = Jido.whereis_agent(c.jido, id)
      assert replacement != server
      assert :ok = Server.await_ready(replacement)
      assert Server.agent(replacement) == committed
      assert Server.snapshot(replacement).state_version == snapshot.state_version
      runtime = Server.children(replacement)[{:plugin, Counter.Runtime}].pid
      assert runtime != plugin.pid
      init = Elixir.Agent.get(runtime, & &1)
      assert init.agent_server == replacement
      assert init.agent_id == id
      assert init.state_version == snapshot.state_version
      assert init.options == [label: "current"]
      assert_receive {:DOWN, ^plugin_ref, :process, _, _}, 1_000
      assert_receive {:DOWN, ^wrapper_ref, :process, _, _}, 1_000
    after
      :ok = :sys.resume(coordinator)
    end

    assert :ok = Controller.await_ready(controller, 5_000)
    assert Controller.status(controller).status == :ready
  end

  test "a coordinator crash preserves Agent, Bus, and Plugin PIDs and state", c do
    {controller, _instance} = start_topology(c.jido, bus: true)
    server = Controller.whereis_agent(controller, :counter)
    bus = Controller.whereis_bus(controller, :events)
    children = Server.children(server)
    {:ok, increment} = Counter.increment_signal(%{})
    assert {:ok, committed} = Server.call(server, increment)
    coordinator = child(controller, Controller.Runtime)
    kill(coordinator)

    eventually(fn ->
      is_pid(child(controller, Controller.Runtime)) and
        child(controller, Controller.Runtime) != coordinator
    end)

    assert :ok = Controller.await_ready(controller, 5_000)
    assert Controller.whereis_agent(controller, :counter) == server
    assert Controller.whereis_bus(controller, :events) == bus
    assert Server.children(server) == children
    assert Server.agent(server) == committed
  end

  test "Bus clients reconnect during manual repair without replacing the Agent", c do
    {controller, instance} = start_topology(c.jido, bus: true)
    server = Controller.whereis_agent(controller, :counter)
    bus = Controller.whereis_bus(controller, :events)
    resource_pool = GenServer.whereis(Controller.name(c.jido, instance.id, :resources))
    :ok = :sys.suspend(resource_pool)

    try do
      kill(bus)
      eventually(fn -> Controller.status(controller).status == :degraded end)
      assert Controller.whereis_agent(controller, :counter) == server
    after
      :ok = :sys.resume(resource_pool)
    end

    assert :ok = Controller.await_ready(controller, 5_000)
    assert Controller.whereis_agent(controller, :counter) == server
    replacement = Controller.whereis_bus(controller, :events)
    assert replacement != bus
    runtime = Server.children(server)[{:plugin, BusInputs}].pid
    assert :ok = BusInputs.Server.ready_snapshot(runtime, timeout: 1_000)
    {:ok, increment} = Counter.increment_signal(%{})
    assert {:ok, [_]} = Jido.Signal.Bus.publish(replacement, [increment])
    eventually(fn -> Server.agent(server).state.count == 1 end)
  end

  test "Agent restart exhaustion stops the instance and cannot be bypassed by repair", c do
    {controller, instance} = start_topology(c.jido, max_restarts: 1, repair: :automatic)
    other = start_supervised!({Server, jido: c.jido, agent: Counter, id: "unrelated"})
    server = Controller.whereis_agent(controller, :counter)
    ref = Process.monitor(controller)
    kill(server)
    eventually(fn -> is_pid(Controller.whereis_agent(controller, :counter)) end)
    replacement = Controller.whereis_agent(controller, :counter)
    assert replacement != server
    kill(replacement)
    assert_receive {:DOWN, ^ref, :process, ^controller, :shutdown}, 2_000
    {:ok, supervisor} = ExUnit.fetch_test_supervisor()

    controller_id = {Controller, instance.id}

    assert {^controller_id, :undefined, :supervisor, _} =
             List.keyfind(Supervisor.which_children(supervisor), {Controller, instance.id}, 0)

    assert Jido.whereis_agent(c.jido, instance.plan.agents["agent/counter"].id) == nil
    assert catch_exit(Controller.reconcile(controller))
    assert Process.alive?(other)
    assert Process.alive?(c.jido_pid)
  end

  for reason <- [:normal, :shutdown] do
    test "#{reason} stays stopped across repair and coordinator restart", c do
      {controller, _instance} = start_topology(c.jido)
      server = Controller.whereis_agent(controller, :counter)
      assert :ok = Server.stop(server, unquote(reason))
      assert :ok = Controller.reconcile(controller)
      eventually(fn -> Controller.status(controller).active == 0 end)

      assert %{status: :degraded, errors: %{"agent/counter" => :member_stopped}} =
               Controller.status(controller)

      coordinator = child(controller, Controller.Runtime)
      kill(coordinator)

      eventually(fn ->
        is_pid(child(controller, Controller.Runtime)) and
          child(controller, Controller.Runtime) != coordinator
      end)

      eventually(fn -> Controller.status(controller).active == 0 end)
      assert Controller.whereis_agent(controller, :counter) == nil
      assert Controller.status(controller).errors["agent/counter"] == :member_stopped
    end
  end

  test "hibernation stays stopped and retains the durable commit", c do
    jido = :"hibernate_#{c.jido}"
    store = {Jido.Persistence.ETS, table: :"store_#{c.jido}"}
    start_supervised!({Jido, name: jido, namespace: Atom.to_string(jido), persistence: store})
    {controller, instance} = start_topology(jido)
    server = Controller.whereis_agent(controller, :counter)
    {:ok, increment} = Counter.increment_signal(%{})
    assert {:ok, committed} = Server.call(server, increment)
    assert :ok = Server.hibernate(server)
    assert :ok = Controller.reconcile(controller)
    eventually(fn -> Controller.status(controller).active == 0 end)
    assert Controller.whereis_agent(controller, :counter) == nil
    pool = Controller.name(jido, instance.id, :agents)
    assert {:ok, restored} = Supervisor.restart_child(pool, "agent/counter")
    assert :ok = Server.await_ready(restored)
    assert Server.agent(restored) == committed
  end

  test "local shutdown removes Plugin trees and leaves other owners alive", c do
    {controller, _instance} = start_topology(c.jido, bus: true)
    other = start_supervised!({Server, jido: c.jido, agent: Counter, id: "unrelated"})
    assert :ok = Server.await_ready(other)
    server = Controller.whereis_agent(controller, :counter)

    pids =
      [server, Controller.whereis_bus(controller, :events)] ++
        Enum.flat_map(Server.children(server), fn {_, child} ->
          [child.pid, child.lifecycle_pid]
        end)

    refs = Enum.map(pids, &{Process.monitor(&1), &1})
    assert :ok = Supervisor.stop(controller)
    for {ref, pid} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 1_000)
    assert Process.alive?(other)
    assert Process.alive?(Server.children(other)[{:plugin, Counter.Runtime}].pid)
  end

  test "failed restart bootstrap stays stopped and preserves the prior checkpoint", c do
    {controller, instance} = start_topology(c.jido)
    server = Controller.whereis_agent(controller, :counter)
    {:ok, signal} = Counter.increment_signal(%{})
    assert {:ok, committed} = Server.call(server, signal)
    pool = Controller.name(c.jido, instance.id, :agents)
    gate = {Counter.Runtime, c.jido}
    :persistent_term.put(gate, :fail)
    on_exit(fn -> :persistent_term.erase(gate) end)
    kill(server)
    eventually(fn -> child(pool, "agent/counter") == :undefined end)
    assert :ok = Controller.reconcile(controller)
    eventually(fn -> Controller.status(controller).active == 0 end)
    assert Controller.status(controller).errors["agent/counter"] == :member_stopped
    :persistent_term.erase(gate)
    assert {:ok, restored} = Supervisor.restart_child(pool, "agent/counter")
    assert :ok = Server.await_ready(restored)
    assert Server.agent(restored) == committed
    assert Server.snapshot(restored).state_version == 1
    assert :ok = Controller.await_ready(controller, 5_000)
  end

  test "logical parent stop policy does not override transient supervision", c do
    instance = Jido.Examples.Topology.Hierarchy.new!(id: unique_id("parent-stop"))

    controller =
      start_supervised!({Controller, jido: c.jido, topology: instance, repair: :manual})

    assert :ok = Controller.await_ready(controller, 5_000)
    parent = Controller.whereis_agent(controller, :leader)
    workers = for member <- 1..3, do: Controller.whereis_agent(controller, :workers, member)
    refs = Enum.map(workers, &{Process.monitor(&1), &1})
    kill(parent)

    for {ref, pid} <- refs,
        do:
          assert_receive(
            {:DOWN, ^ref, :process, ^pid, {:shutdown, {:parent_down, :killed}}},
            1_000
          )

    assert :ok = Controller.reconcile(controller)
    eventually(fn -> Controller.status(controller).active == 0 end)
    assert is_pid(Controller.whereis_agent(controller, :leader))
    assert Enum.all?(1..3, &(Controller.whereis_agent(controller, :workers, &1) == nil))
    assert Controller.status(controller).status == :degraded
  end

  test "replacement target removes members through subtree shutdown", c do
    {controller, instance} = start_topology(c.jido)
    server = Controller.whereis_agent(controller, :counter)
    ref = Process.monitor(server)

    smaller =
      Jido.Topology.new!(%{name: "removed", agents: []})
      |> Jido.Topology.instantiate(id: instance.id)
      |> Jido.Topology.unwrap!()

    assert {:error, %Jido.Error.ValidationError{}} = Controller.update(controller, smaller)
    assert Process.alive?(server)
    stop_supervised!({Controller, instance.id})
    assert_receive {:DOWN, ^ref, :process, ^server, :shutdown}, 1_000
    replacement = start_supervised!({Controller, jido: c.jido, topology: smaller})
    assert :ok = Controller.await_ready(replacement, 5_000)
    assert Controller.status(replacement).agents == 0
    assert Jido.whereis_agent(c.jido, instance.plan.agents["agent/counter"].id) == nil
  end

  test "a replacement instance waits for old target cleanup", c do
    instance = Jido.Examples.Topology.Independent.new!(id: unique_id("target-cleanup"))
    controller = start_supervised!({Controller, jido: c.jido, topology: instance})
    assert :ok = Controller.await_ready(controller, 5_000)

    expanded =
      Jido.Topology.new!(%{
        instance.definition
        | agents: instance.definition.agents ++ [%{key: :extra, module: Counter}]
      })
      |> Jido.Topology.instantiate(id: instance.id)
      |> Jido.Topology.unwrap!()

    assert :ok = Controller.update(controller, expanded)
    assert :ok = Controller.await_ready(controller, 5_000)
    owner_name = Controller.name(c.jido, instance.id, :owner)
    owner = GenServer.whereis(owner_name)
    :erlang.suspend_process(owner)

    try do
      stop_supervised!({Controller, instance.id})
      {:ok, supervisor} = ExUnit.fetch_test_supervisor()

      start =
        Task.async(fn ->
          Supervisor.start_child(supervisor, {Controller, jido: c.jido, topology: instance})
        end)

      eventually(fn -> is_pid(Controller.whereis(c.jido, instance.id)) end)
      assert GenServer.whereis(owner_name) == owner
      :erlang.resume_process(owner)
      assert {:ok, replacement} = Task.await(start)
      assert :ok = Controller.await_ready(replacement, 5_000)
      assert Controller.status(replacement).agents == 2
      assert Controller.status(replacement).target_revision == 0
      assert Controller.whereis_agent(replacement, :extra) == nil
    after
      if Process.alive?(owner), do: :erlang.resume_process(owner)
    end
  end

  test "invalid restart limits are rejected before starting an instance", c do
    instance = Jido.Examples.Topology.Independent.new!(id: unique_id("limits"))

    for opts <- [[max_restarts: -1], [max_restarts: :infinity], [max_seconds: 0]] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Controller.start_link([jido: c.jido, topology: instance] ++ opts)
    end
  end

  test "pending ownership cleanup returns its startup error without an OTP wrapper", c do
    Process.flag(:trap_exit, true)
    {controller, instance} = start_topology(c.jido)
    owner = GenServer.whereis(Controller.name(c.jido, instance.id, :owner))
    :erlang.suspend_process(owner)

    try do
      assert :ok = Supervisor.stop(controller)

      assert {:error, :ownership_cleanup_pending} =
               Controller.start_link(jido: c.jido, topology: instance)
    after
      if Process.alive?(owner), do: :erlang.resume_process(owner)
    end
  end

  defp start_topology(jido, opts \\ []) do
    bus? = Keyword.get(opts, :bus, false)

    definition =
      Jido.Topology.new!(%{
        name: "otp_supervision",
        agents: [%{key: :counter, module: Counter}],
        resources: if(bus?, do: [%{key: :events, kind: :bus}], else: []),
        connections:
          if(bus?, do: [%{agent: :counter, to: :events, path: "supervised.increment"}], else: []),
        startup: [retry_interval: 10]
      })

    instance =
      Jido.Topology.instantiate(definition, id: unique_id("otp")) |> Jido.Topology.unwrap!()

    controller =
      start_supervised!(
        {Controller,
         Keyword.merge(
           [jido: jido, topology: instance, repair: :manual],
           Keyword.drop(opts, [:bus])
         )}
      )

    assert :ok = Controller.await_ready(controller, 5_000)
    {controller, instance}
  end

  defp child(supervisor, id) do
    case List.keyfind(Supervisor.which_children(supervisor), id, 0) do
      {^id, pid, _, _} -> pid
      _ -> nil
    end
  end

  defp kill(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 1_000
  end
end
