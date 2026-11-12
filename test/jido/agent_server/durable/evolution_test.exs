defmodule Jido.AgentServer.Durable.EvolutionTest do
  use Jido.Test.Case, async: true
  use Covenant.Case, component: "jido.agent_server.durable", async: true

  alias Jido.AgentServer, as: Server
  import Jido.Test.Eventually

  defmodule Increment do
    use Jido.Action, name: "definition_upgrade_increment"

    @impl true
    def run(_input, context), do: {:ok, %{count: context.agent_state.count + 1}}
  end

  defmodule Gate do
    use Jido.Action, name: "definition_upgrade_gate"

    @impl true
    def run(_input, context) do
      send(context.observer, {:gate_started, self()})
      receive do: (:release -> {:ok, context.agent_state})
    end
  end

  defmodule Migrate do
    use Jido.Action,
      name: "definition_upgrade_migrate",
      schema: Jido.Joi.object(%{state: Jido.Joi.map()})

    @impl true
    def run(%{state: %{count: count}}, _context), do: {:ok, %{total: count + 10}}
  end

  defmodule V1 do
    use Jido.Agent, name: "definition_upgrade_v1", vsn: 1

    state do
      schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end

    routes do
      route "increment", Increment

      route "gate", Gate do
        state(:unchanged)
      end
    end
  end

  defmodule V2 do
    use Jido.Agent, name: "definition_upgrade_v2", vsn: 2

    state do
      schema Jido.Joi.object(%{total: Jido.Joi.integer()})
    end

    routes do
      route "increment" do
        action _input, context: context do
          {:ok, %{total: context.agent_state.total + 1}}
        end
      end
    end
  end

  defp document_and_catalog do
    definition = V2.definition()
    catalog = Jido.Test.AgentServer.Registry.for(definition)
    {:ok, document} = Jido.Test.AgentServer.Registry.encode(definition, catalog)
    {document, catalog}
  end

  defp start(c, opts \\ []) do
    agent = V1.instantiate!(id: unique_id("definition-upgrade"), state: %{count: 2})
    assert {:ok, server} = Jido.start_agent(c.jido, agent, opts)
    assert :ok = Server.await_ready(server)
    {:ok, ref} = Jido.agent_ref(c.jido, agent.id)
    {agent, server, ref}
  end

  defp current_server(jido, ref, previous) do
    eventually(fn ->
      case Jido.resolve_agent(jido, ref) do
        {:ok, pid} when pid != previous -> pid
        _ -> nil
      end
    end)
  end

  @tag obligation: ["jido.agent_server.durable.I11", "jido.agent_server.durable.I12"]
  test "a complete definition upgrade keeps the stable Ref and replaces the PID", c do
    {_agent, server, ref} = start(c)
    {document, catalog} = document_and_catalog()

    assert {:ok, upgraded, []} =
             Server.upgrade(server, document, catalog: catalog, migrate: Migrate)

    assert upgraded.module == V2
    assert upgraded.vsn == 2
    assert upgraded.state == %{total: 12}

    replacement = current_server(c.jido, ref, server)
    refute Process.alive?(server)
    assert :ok = Server.await_ready(replacement)
    assert %{agent: ^upgraded, state_version: 1} = Server.snapshot(replacement)

    signal = Jido.Signal.new!("increment", %{}, source: "/test")
    assert {:ok, next, []} = Jido.call(c.jido, ref, signal)
    assert next.state == %{total: 13}
  end

  @tag obligation: "jido.agent_server.durable.I12"
  test "upgrade rejects active work and never queues behind it", c do
    {agent, server, _ref} = start(c)
    {document, catalog} = document_and_catalog()
    signal = Jido.Signal.new!("gate", %{}, source: "/test")
    observer = self()

    task = Task.async(fn -> Server.call(server, signal, context: %{observer: observer}) end)
    assert_receive {:gate_started, worker}

    assert {:error, :agent_busy} =
             Server.upgrade(server, document, catalog: catalog, migrate: Migrate)

    assert Server.agent(server) == agent
    send(worker, :release)
    assert {:ok, ^agent, []} = Task.await(task)
  end

  @tag obligation: "jido.agent_server.durable.I12"
  test "upgrade requires a trusted Catalog and a valid complete migrated state", c do
    {agent, server, _ref} = start(c)
    {document, catalog} = document_and_catalog()

    assert {:error, _} = Server.upgrade(server, document)
    assert {:error, _} = Server.upgrade(server, document, catalog: catalog)
    assert Server.agent(server) == agent
    assert Server.status(server).state_version == 0
  end

  @tag obligation: "jido.agent_server.durable.I12"
  test "persistent upgrade saves the new definition before restart", c do
    store = {Jido.Persistence.ETS, table: __MODULE__}
    {initial, server, ref} = start(c, persistence: store)
    {document, catalog} = document_and_catalog()

    assert {:ok, upgraded, []} =
             Server.upgrade(server, document, catalog: catalog, migrate: Migrate)

    assert {:ok, ^upgraded, 1} =
             Jido.Persistence.load_agent_with_revision(
               store,
               upgraded.module,
               initial.id,
               instance: c.jido
             )

    replacement = current_server(c.jido, ref, server)
    assert %{agent: ^upgraded, state_version: 1} = Server.snapshot(replacement)
  end
end
