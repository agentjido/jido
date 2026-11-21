defmodule Jido.AgentServer.Composition.TopologyRemovalTest do
  use Jido.Test.Case, async: false
  use Covenant.Case, component: "jido.agent_server.composition", async: false

  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server

  defmodule Work do
    use Jido.Action,
      name: "topology_removal_work",
      schema: Jido.Joi.object(%{block: Jido.Joi.boolean()}),
      output_schema: Jido.Joi.object(%{completed: Jido.Joi.integer()})

    @impl true
    def run(%{block: block}, context) do
      if block do
        %{gate: gate, observer: observer} = context
        send(observer, {:topology_work_blocked, gate, self()})

        receive do
          {:release, ^gate} -> :ok
        end
      end

      {:ok, %{completed: context.agent_state.completed + 1}}
    end
  end

  defmodule Ping do
    use Jido.Action,
      name: "topology_removal_ping",
      schema: Jido.Joi.object(%{}),
      output_schema: Jido.Joi.object(%{pings: Jido.Joi.integer()})

    @impl true
    def run(_input, context), do: {:ok, %{pings: context.agent_state.pings + 1}}
  end

  defmodule Worker do
    use Jido.Agent, name: "topology_removal_worker"

    state do
      schema Jido.Joi.object(%{completed: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end

    routes do
      signal_source "/test/topology-removal/worker"
      route "test.topology_removal.work", Work, as: :work
    end
  end

  defmodule Team do
    use Jido.Agent, name: "topology_removal_team"

    topology do
      agent :workers, Worker do
        count 2
      end
    end
  end

  defmodule Department do
    use Jido.Agent, name: "topology_removal_department"

    topology do
      agent :teams, Team do
        count 2
      end
    end
  end

  defmodule Company do
    use Jido.Agent, name: "topology_removal_company"

    state do
      schema Jido.Joi.object(%{pings: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end

    routes do
      signal_source "/test/topology-removal/company"
      route "test.topology_removal.ping", Ping, as: :ping
    end

    topology do
      agent :departments, Department do
        count 2
      end
    end
  end

  @tag obligation: "jido.agent_server.composition.I11"
  test "removal stops one selected subtree and keeps the root and sibling alive", c do
    id = unique_id("topology-removal")
    root = start_company(c.jido, id)
    selected = subtree(c.jido, id, 1)
    sibling = subtree(c.jido, id, 2)

    assert map_size(selected) == 7
    assert map_size(sibling) == 7
    selected_monitors = Map.new(selected, fn {_id, pid} -> {pid, Process.monitor(pid)} end)

    assert :ok = Server.remove_topology_member(root, :departments, 1)

    for {pid, monitor} <- selected_monitors do
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 5_000
    end

    assert Process.alive?(root)
    assert Enum.all?(sibling, fn {_id, pid} -> Process.alive?(pid) end)
    assert Jido.resident_agent_count(c.jido) == 8

    assert {:ok, %Server.TurnResult{status: :committed}} =
             Server.call(root, Company.ping_signal!(%{}))

    assert Server.snapshot(root).agent.state.pings == 1
    assert :ok = Server.remove_topology_member(root, :departments, 1)

    assert {:error, :topology_member_not_found} =
             Server.remove_topology_member(root, :departments, 3)

    activation = Jido.Test.AgentServer.ExampleRuntime.activation(root)
    monitor = Process.monitor(root)
    Process.exit(root, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^root, :killed}, 5_000

    recovered =
      eventually(fn ->
        case Jido.AgentServer.Supervisor.worker(activation) do
          pid when is_pid(pid) and pid != root -> pid
          _other -> nil
        end
      end)

    assert :ok = Server.await_ready(recovered)
    assert Jido.resident_agent_count(c.jido) == 8
    assert subtree(c.jido, id, 1) == %{}
    assert :ok = Server.remove_topology_member(recovered, :departments, 1)
  end

  @tag obligation: "jido.agent_server.composition.I11"
  test "a timed out removal closes admission and a retry finishes cleanup", c do
    id = unique_id("topology-removal-timeout")
    root = start_company(c.jido, id)
    {_id, worker} = Enum.find(subtree(c.jido, id, 1), &worker?/1)
    gate = make_ref()
    observer = self()

    turn =
      Task.async(fn ->
        Server.call(worker, Worker.work_signal!(%{block: true}), context: %{gate: gate, observer: observer})
      end)

    assert_receive {:topology_work_blocked, ^gate, action}, 1_000

    assert {:error, {:topology_removal_incomplete, :quiesce_timeout}} =
             Server.remove_topology_member(root, :departments, 1, timeout: 25)

    assert Process.alive?(root)

    assert {:ok, %Server.TurnResult{status: :committed}} =
             Server.call(root, Company.ping_signal!(%{}))

    assert Server.status(worker).admission in [:quiescing, :quiesced]

    assert {:error, :quiesced} =
             Server.call(worker, Worker.work_signal!(%{block: false}))

    send(action, {:release, gate})
    assert {:ok, %Server.TurnResult{status: :committed}} = Task.await(turn, 5_000)
    assert_eventually(Server.status(worker).admission == :quiesced)

    assert :ok =
             Server.remove_topology_member(root, :departments, 1, timeout: 5_000)

    refute Process.alive?(worker)
    assert Jido.resident_agent_count(c.jido) == 8
  end

  @tag obligation: "jido.agent_server.composition.I11"
  test "removal keeps durable child state for a replacement root activation", c do
    c = restart_jido!(c, {Jido.Persistence.File, path: c.tmp_dir})
    id = unique_id("topology-removal-persistence")
    root = start_company(c.jido, id)
    {worker_id, worker} = Enum.find(subtree(c.jido, id, 1), &worker?/1)

    assert {:ok, %Server.TurnResult{status: :committed}} =
             Server.call(worker, Worker.work_signal!(%{block: false}))

    assert Server.snapshot(worker).agent.state.completed == 1
    assert :ok = Server.remove_topology_member(root, :departments, 1)
    assert Jido.whereis_agent(c.jido, worker_id) == nil

    activation = Jido.Test.AgentServer.ExampleRuntime.activation(root)
    monitor = Process.monitor(activation)
    Process.exit(activation, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^activation, :killed}, 5_000

    replacement =
      eventually(fn ->
        case Jido.whereis_agent(c.jido, id) do
          pid when is_pid(pid) and pid != root -> pid
          _other -> nil
        end
      end)

    assert :ok = Server.await_ready(replacement)
    restored = Map.fetch!(Map.new(Jido.list_agents(c.jido)), worker_id)
    assert Server.snapshot(restored).agent.state.completed == 1
    assert Jido.resident_agent_count(c.jido) == 15
  end

  @tag obligation: "jido.agent_server.composition.I11"
  test "explicit cancellation stops an accepted pre-commit turn", c do
    id = unique_id("topology-removal-cancel")
    root = start_company(c.jido, id)
    {_id, worker} = Enum.find(subtree(c.jido, id, 1), &worker?/1)
    gate = make_ref()
    observer = self()

    turn =
      Task.async(fn ->
        Server.call(worker, Worker.work_signal!(%{block: true}), context: %{gate: gate, observer: observer})
      end)

    assert_receive {:topology_work_blocked, ^gate, _action}, 1_000

    assert :ok =
             Server.remove_topology_member(root, :departments, 1,
               active: :cancel,
               timeout: 5_000
             )

    assert {:ok, %Server.TurnResult{status: :cancelled}} = Task.await(turn, 5_000)
    assert Process.alive?(root)
    assert Jido.resident_agent_count(c.jido) == 8
  end

  defp start_company(jido, id) do
    assert {:ok, root} = Jido.start_agent(jido, Company, id: id)
    assert :ok = Server.await_ready(root)
    assert Jido.resident_agent_count(jido) == 15
    root
  end

  defp subtree(jido, root_id, slot) do
    prefix = root_id <> "/$topology/departments/#{slot}"

    jido
    |> Jido.list_agents()
    |> Enum.filter(fn {id, _pid} -> id == prefix or String.starts_with?(id, prefix <> "/") end)
    |> Map.new()
  end

  defp worker?({_id, pid}), do: Server.snapshot(pid).agent.module == Worker
end
