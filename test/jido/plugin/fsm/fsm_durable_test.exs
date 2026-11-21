defmodule Jido.Plugin.FSMDurableTest do
  use Covenant.Case, component: "jido.plugin.fsm", async: false

  import Jido.Test.Case, only: [unique_id: 1]

  @moduletag :tmp_dir

  alias Jido.Persistence
  alias Jido.Persistence.{Record, Store}
  alias Jido.Plugin.FSM
  alias Jido.AgentServer, as: Server

  defmodule Approval do
    use Jido.Flow,
      name: "fsm_durable_approval",
      schema: Jido.Joi.object(%{request_id: Jido.Joi.string()})

    flow do
      selection "decision" do
        await "approved", event: "approved", match: %{request_id: input(:request_id)}
        timer "expired", after_ms: 3_600_000
      end

      step "finish", decision <- result("decision"), inline: [context: context] do
        status = if decision.selected == "approved", do: :approved, else: :expired
        {:ok, %{context.agent_state | status: status}}
      end

      output result("finish")
    end
  end

  defmodule Agent do
    use Jido.Agent,
      name: "fsm_durable_agent",
      plugins: [{FSM, %{definition_vsn: 1}}]

    state do
      schema(
        Jido.Joi.object(%{
          status: Jido.Joi.enum([:idle, :approved, :expired]) |> Jido.Joi.default(:idle)
        })
      )
    end

    state_machine do
      initial :idle
      terminal(:ready)
      transition(:approve, from: :idle, route: :approve, to: :ready)
    end

    routes do
      signal_source "/plugin/fsm/durable"
      route "request", Approval, as: :approve
    end
  end

  defmodule UpgradeFSM do
    use Jido.Action, name: "upgrade_beta_fsm"

    @impl true
    def run(%{snapshot: %{agent: saved}}, _context) do
      plugins =
        Enum.map(saved.plugins, fn
          %{provider: Jido.Agent.Plugin.FSM} = plugin -> %{plugin | provider: FSM}
          plugin -> plugin
        end)

      with {:ok, next} <- Persistence.snapshot(%{saved | plugins: plugins, vsn: saved.vsn + 1}),
           do: {:ok, %{snapshot: next}}
    end
  end

  @tag obligation: "jido.plugin.fsm.I2"
  test "a durable Flow wait keeps the source FSM state until completion", c do
    id = unique_id("fsm-wait")
    instance = String.to_atom("fsm_durable_#{System.unique_integer([:positive])}")
    namespace = "jido/test/fsm-durable/#{System.unique_integer([:positive])}"

    start_supervised!(
      {Jido,
       name: instance,
       namespace: namespace,
       persistence: {Jido.Persistence.File, path: c.tmp_dir},
       activation: [idle_residency_timeout: 5_000]},
      id: instance
    )

    address = Jido.Agent.Address.new!(namespace: namespace, id: id)
    assert {:ok, ^address} = Jido.create_agent(instance, address, Agent)

    request =
      Jido.Signal.new!("request", %{request_id: "one"}, source: "/plugin/fsm/durable")

    pending = Jido.submit(instance, address, request)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :waiting, waits: [wait]}} =
             Server.await(pending)

    assert %Jido.AgentServer.Status{work_state: :waiting, waits: [^wait]} =
             Jido.status(instance, address)

    assert {:ok, server} = Jido.resolve_agent(instance, address)

    assert Server.snapshot(server).agent.state == %{
             status: :idle,
             fsm: %{definition_vsn: 1, current: :idle}
           }

    approval =
      Jido.Signal.new!("approved", %{request_id: "one"}, source: "/plugin/fsm/durable")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.call(instance, address, approval)

    assert {:ok, server} = Jido.resolve_agent(instance, address)
    completed = Server.snapshot(server).agent
    assert completed.state.status == :approved
    assert completed.state.fsm == %{definition_vsn: 1, current: :ready}
  end

  @tag obligation: "jido.plugin.fsm.I3"
  test "an inactive beta checkpoint needs an explicit upgrade and keeps its FSM state", c do
    source = {Persistence.File, path: c.tmp_dir}
    id = unique_id("beta-fsm")
    opts = [namespace: "beta-fsm"]
    address = Jido.Agent.Address.new!(namespace: opts[:namespace], id: id)
    agent = Agent.instantiate!(id: id, state: %{status: :approved, fsm: %{current: :ready}})
    assert {:ok, snapshot} = Persistence.snapshot(agent)
    assert [plugin] = snapshot.agent.plugins

    legacy = Jido.Agent.Plugin.FSM
    legacy_name = Atom.to_string(legacy)

    # The Term codec records loaded provider modules in its header.
    Module.create(legacy, quote(do: nil), Macro.Env.location(__ENV__))

    record =
      try do
        legacy_snapshot = %{
          snapshot
          | agent: %{snapshot.agent | plugins: [%{plugin | provider: legacy}]},
            references: snapshot.references |> Map.delete(FSM) |> Map.put(legacy, legacy.module_info(:md5))
        }

        assert {:ok, record} = Record.build_active(agent, address, 0, 0, legacy_snapshot)
        assert {:ok, bytes} = Record.encode(record)
        bytes
      after
        :code.delete(legacy)
        :code.purge(legacy)
      end

    assert :ok = Store.compare_and_swap(source, Record.agent_key(address), :not_found, record)

    assert {:error, {:unavailable_persistence_module, ^legacy_name}} =
             Persistence.load_agent(source, Agent, id, opts)

    assert {:ok, upgraded, 1} =
             Persistence.upgrade_agent(source, Agent, id, UpgradeFSM, opts ++ [legacy_modules: [legacy]])

    assert upgraded.vsn == agent.vsn + 1
    assert upgraded.state == %{status: :approved, fsm: %{definition_vsn: 1, current: :ready}}
    assert upgraded.plugins == [plugin]
    assert {:ok, ^upgraded, 1} = Persistence.load_agent_with_revision(source, Agent, id, opts)
  end
end
