Code.require_file("../support/topology/corpus.exs", __DIR__)

defmodule JidoTest.Authoring.Topology.ExecutionTest do
  use JidoTest.Case, async: false
  @moduletag :authoring

  alias Jido.AgentServer, as: Server
  alias Jido.Signal.Bus
  alias Jido.Topology
  alias Jido.Topology.Controller
  alias JidoTest.Authoring.Topology.{Corpus, Fixtures}

  # Choose a leaf in each local case so that a restart also tests stable group
  # keys, included component paths, or contributed subscriptions where present.
  @members [
    minimal: "agent/worker",
    minimal_keyword: "agent/worker",
    counted: "group/workers/1",
    keyed: "group/workers/a%2Fb",
    ownership: "agent/child",
    bus: "agent/worker",
    nested: "component/team/agent/worker",
    repeated: "component/team%2Fa/agent/worker",
    deep: "component/region/component/team/group/workers/1",
    plugin: "group/workers/1",
    combined: "agent/worker"
  ]

  setup %{variant: variant, form: form, jido: jido} do
    Corpus.load!(variant)
    spec = Corpus.spec(variant)
    scenario = hd(spec.scenarios)
    definition = Corpus.definition(spec, form)

    instance =
      Topology.instantiate(definition, id: "corpus", input: scenario.input) |> Topology.unwrap!()

    controller = start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})
    assert :ok = Controller.await_ready(controller, 5_000)
    {:ok, spec: spec, scenario: scenario, definition: definition, controller: controller}
  end

  for {variant, key} <- @members, form <- Corpus.forms() do
    @tag variant: variant, form: form, member: key
    test "#{variant}/#{form}: committed state and declared wiring survive OTP restart", c do
      plan = c.scenario.plan

      agents =
        Map.new(plan.agents, fn {key, member} ->
          pid = Jido.whereis_agent(c.jido, member.id)
          agent = Server.agent(pid)

          defaults =
            if member.module == Fixtures.PluginWorker,
              do: %{value: 0},
              else: %{label: "worker", value: 0}

          assert agent.id == member.id
          assert agent.module == member.module
          assert agent.state == Map.merge(defaults, member.initial_state)
          assert Server.snapshot(pid).state_version == 0
          {key, pid}
        end)

      member = Map.fetch!(plan.agents, c.member)
      original = Map.fetch!(agents, c.member)
      assert {:ok, committed} = Server.call(original, work(41))
      old_runtime = monitor_runtime([original])
      Process.exit(original, :kill)
      assert_down(old_runtime)

      eventually(fn -> is_pid(Jido.whereis_agent(c.jido, member.id)) end)
      replacement = Jido.whereis_agent(c.jido, member.id)
      assert replacement != original
      assert :ok = Server.await_ready(replacement)
      assert Server.agent(replacement) == committed
      assert Server.snapshot(replacement).state_version == 1

      # OTP has already replaced the process. Only logical parent repair needs
      # an explicit pass in manual mode.
      if member.parent, do: assert(:ok = Controller.reconcile(c.controller))
      assert :ok = Controller.await_ready(c.controller, 5_000)

      for {key, pid} <- Map.delete(agents, c.member) do
        assert Jido.whereis_agent(c.jido, plan.agents[key].id) == pid
      end

      if member.parent do
        parent = Map.fetch!(agents, member.parent)
        assert Server.status(replacement).runtime.parent.pid == parent
        assert Server.children(parent)[c.member].pid == replacement
      end

      buses =
        Map.new(plan.resources, fn {key, resource} ->
          assert {:ok, pid} = Bus.whereis(resource.id, jido: c.jido)
          {key, pid}
        end)

      case member.subscriptions do
        [] ->
          assert {:ok, _} = Server.call(replacement, work(42))

        [subscription | _] ->
          assert {:ok, [_]} = Bus.publish(Map.fetch!(buses, subscription.bus), [work(42)])
          eventually(fn -> Server.snapshot(replacement).state_version == 2 end)
      end

      assert Server.agent(replacement).state == %{committed.state | value: 42}
      assert Server.snapshot(replacement).state_version == 2
      assert Corpus.definition(c.spec, c.form) == c.definition
      live = Map.put(agents, c.member, replacement) |> Map.values()
      monitors = monitor_runtime(live ++ Map.values(buses), live)
      assert :ok = Supervisor.stop(c.controller)
      assert_down(monitors)
      assert Jido.agent_count(c.jido) == 0
    end
  end

  for form <- Corpus.forms() do
    @tag variant: :minimal, form: form
    test "#{form}: a clean stop remains stopped after reconciliation", c do
      original = Controller.whereis_agent(c.controller, :worker)
      ref = Process.monitor(original)
      assert :ok = Server.stop(original)
      assert_receive {:DOWN, ^ref, :process, ^original, :shutdown}, 1_000
      assert :ok = Controller.reconcile(c.controller)
      eventually(fn -> Controller.status(c.controller).active == 0 end)

      assert %{status: :degraded, errors: %{"agent/worker" => :member_stopped}} =
               Controller.status(c.controller)

      assert Controller.whereis_agent(c.controller, :worker) == nil
      assert :ok = Supervisor.stop(c.controller)
      assert Jido.agent_count(c.jido) == 0
    end
  end

  defp work(value),
    do: Jido.Signal.new!("authoring.work", %{value: value}, source: "/authoring/test")

  defp monitor_runtime(agents), do: monitor_runtime(agents, agents)

  defp monitor_runtime(pids, agents) do
    plugins =
      for agent <- agents,
          {_, %{kind: :plugin} = child} <- Server.children(agent),
          pid <- [child.pid, child.lifecycle_pid],
          is_pid(pid),
          do: pid

    for pid <- Enum.uniq(pids ++ plugins), do: {pid, Process.monitor(pid)}
  end

  defp assert_down(monitors) do
    for {pid, ref} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 5_000)
  end
end
