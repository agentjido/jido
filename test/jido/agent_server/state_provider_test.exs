defmodule Jido.AgentServer.StateProviderTest do
  use Covenant.Case, component: "jido.agent_server", async: false

  alias Jido.AgentServer

  defmodule Provider do
    @behaviour Jido.AgentServer.StateProvider

    @impl true
    def compile_state!(:count, _env) do
      {Jido.Joi.object(%{count: Jido.Joi.integer()}), :count}
    end

    @impl true
    def open(:count, _context, _mode, agent, open), do: open.(agent)

    @impl true
    def refresh(:count, _context, agent), do: {:ok, agent}

    @impl true
    def commit(:count, _context, _before, %{state: %{count: 3}}, _save),
      do: {:error, {:rejected, :not_allowed}}

    def commit(:count, _context, _before, %{state: %{count: 6}} = candidate, save) do
      result = save.(candidate)
      send(Process.whereis(Jido.AgentServer.StateProviderTest), {:saved, self()})

      receive do
        :complete -> result
      after
        4_000 -> {:error, :indeterminate}
      end
    end

    def commit(:count, _context, _before, candidate, save) do
      {:ok, canonical} = Jido.Agent.set(candidate, count: candidate.state.count * 2)
      save.(canonical)
    end
  end

  defmodule RowProvider do
    @behaviour Jido.AgentServer.StateProvider

    @impl true
    defdelegate compile_state!(option, env), to: Provider

    @impl true
    def startup_id(:count, id) when is_binary(id), do: {:ok, id}
    def startup_id(:count, _), do: {:error, :row_id_required}

    @impl true
    def open(:count, _context, :create, %{id: "slow"} = agent, open) do
      send(Process.whereis(Jido.AgentServer.StateProviderTest), {:opening, self()})

      receive do
        :open -> populate(agent, open)
      end
    end

    def open(:count, _context, :create, agent, open), do: populate(agent, open)
    def open(:count, _context, :restore, agent, open), do: open.(agent)

    defp populate(agent, open) do
      with {:ok, populated} <- Jido.Agent.instantiate(Jido.Agent.definition(agent), id: agent.id, state: %{count: 0}),
           do: open.(populated)
    end

    @impl true
    defdelegate refresh(option, context, agent), to: Provider

    @impl true
    defdelegate commit(option, context, before, candidate, save), to: Provider
  end

  defmodule RowCounter do
    use Jido.Agent, name: "row_counter"

    state do
      state_provider(RowProvider, :count)
    end
  end

  defmodule SetCount do
    use Jido.Action, name: "provider_set_count", schema: Jido.Joi.object(%{count: Jido.Joi.integer()})

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule Counter do
    use Jido.Agent, name: "provider_counter"
    import Jido.Agent.DSL.State, only: [state_provider: 2]

    state do
      state_provider(Provider, :count)
    end

    routes do
      route "count.set", SetCount
    end
  end

  @tag obligation: "jido.agent_server.I108"
  test "the provider commits canonical state and a rejected write leaves the agent usable" do
    start_supervised!(
      {Jido, name: Runtime, namespace: "test/state-provider", persistence: {Jido.Persistence.ETS, table: Store}}
    )

    {:ok, address} = Jido.agent_address(Runtime, "counter")
    assert {:ok, ^address} = Jido.create_agent(Runtime, address, Counter, state: %{count: 0})

    assert {:error, :state_provider_replacement_unsupported} =
             Jido.replace_agent(Runtime, address, Counter, expected: Jido.Agent.definition(Counter))

    assert {:ok, server} = Jido.activate_agent(Runtime, address)
    assert {:error, :state_provider_upgrade_unsupported} = Jido.upgrade_agent(Runtime, address, SetCount)
    assert Process.alive?(server)

    assert {:ok, %{status: :committed}} = AgentServer.call(server, signal(2))
    assert %{agent: %{state: %{count: 4}}} = AgentServer.snapshot(server)
    assert {:ok, %{state: %{count: 4}}, _, _, _} = Jido.Persistence.load_agent_address(Runtime, address)

    assert {:ok, %{status: :failed, error: :not_allowed}} = AgentServer.call(server, signal(3))
    assert %{agent: %{state: %{count: 4}}} = AgentServer.snapshot(server)
    assert {:ok, %{status: :committed}} = AgentServer.call(server, signal(4))
    assert %{agent: %{state: %{count: 8}}} = AgentServer.snapshot(server)
  end

  @tag obligation: "jido.agent_server.I108"
  test "closes admission while a retained result is already readable from storage" do
    Process.register(self(), __MODULE__)

    start_supervised!(
      {Jido, name: Runtime, namespace: "test/state-provider", persistence: {Jido.Persistence.ETS, table: Store}}
    )

    {:ok, address} = Jido.agent_address(Runtime, "retained-counter")
    assert {:ok, ^address} = Jido.create_agent(Runtime, address, Counter, state: %{count: 0})
    assert {:ok, server} = Jido.activate_agent(Runtime, address)
    pending = Jido.submit(Runtime, address, signal(6), turn_id: "retained", result_handoff: true)

    assert_receive {:saved, writer}, 2_000
    assert {:ok, %{status: :committed}} = Jido.turn_result(Runtime, address, "retained")
    assert %{admission: :blocked} = AgentServer.status(server)
    assert %{agent: %{state: %{count: 0}}} = AgentServer.snapshot(server)
    send(writer, :complete)
    assert {:ok, %{status: :committed}} = AgentServer.await(pending)
  end

  @tag obligation: "jido.agent_server.I109"
  test "rejects a Catalog schema override for a compiled provider" do
    definition = RowCounter.definition()

    targets = fn schema ->
      %{{"test/agent", 1} => RowCounter, {"test/schema", 1} => schema}
    end

    registry = Jido.Catalog.from_targets!(__MODULE__, :jido, targets.(definition.schema))
    opts = fn catalog -> [catalog: catalog, codec: Jido.Agent.Codec] end
    assert {:ok, json} = Jido.Codec.encode_json(definition, opts.(registry))
    assert {:ok, ^definition} = Jido.Codec.decode_json(json, opts.(registry))

    alternate = Jido.Catalog.from_targets!(__MODULE__, :jido, targets.(Jido.Joi.object(%{count: Jido.Joi.any()})))

    assert {:error, [%{code: :state_provider_schema_mismatch, path: ["definition", "schema"]}]} =
             Jido.Codec.decode_json(json, opts.(alternate))
  end

  @tag obligation: "jido.agent_server.I109"
  test "addressed creation uses the row source and verifies its ID" do
    start_runtime()
    source = fn id -> %Jido.AgentServer.StateProvider.Source{provider: RowProvider, input: id} end

    assert {:error, %{code: :state_source_address_mismatch}} =
             Jido.create_agent(Runtime, elem(Jido.agent_address(Runtime, "other"), 1), RowCounter,
               state: source.("row")
             )

    {:ok, address} = Jido.agent_address(Runtime, "row")
    assert {:ok, ^address} = Jido.create_agent(Runtime, address, RowCounter, state: source.("row"))
    assert {:ok, %{state: %{count: 0}}, _, _, _} = Jido.Persistence.load_agent_address(Runtime, address)
    assert {:error, :row_id_required} = Jido.start_agent(Runtime, RowCounter)

    raw = RowCounter.instantiate!(id: "row", state: %{count: 10})
    assert {:error, :row_id_required} = Jido.start_agent(Runtime, raw)
    assert {:error, :row_id_required} = Jido.create_agent(Runtime, address, raw)

    assert {:error, %{code: :duplicate_start_options}} =
             Jido.start_agent(Runtime, RowCounter, state: source.("one"), state: source.("two"))
  end

  @tag obligation: "jido.agent_server.I109"
  test "checkpoint verifies the provider and its declaring module" do
    agent = Counter.instantiate!(id: "row", state: %{count: 0})
    assert {:ok, snapshot} = Jido.Persistence.Snapshot.dump(agent, %{}, fn _, state -> {:ok, state} end)
    assert %{state_provider: Provider} = snapshot
    assert is_map_key(snapshot.references, Provider)
    assert is_map_key(snapshot.references, Counter)
    missing_provider = put_in(snapshot.agent.module, nil)

    assert {:error, %{code: :changed_state_provider}} =
             Jido.Persistence.Snapshot.load(missing_provider, %{}, fn _, state -> {:ok, state} end)
  end

  @tag obligation: "jido.agent_server.I109"
  test "startup waits using the instance persistence budget" do
    Process.register(self(), __MODULE__)

    options = [
      name: Runtime,
      namespace: "test/slow-state-provider",
      persistence: {Jido.Persistence.ETS, table: Store},
      agent_server: [persistence_timeout: 7_000]
    ]

    start_supervised!({Jido, options})
    source = %Jido.AgentServer.StateProvider.Source{provider: RowProvider, input: "slow"}
    task = Task.async(fn -> Jido.start_agent(Runtime, RowCounter, state: source) end)
    assert_receive {:opening, opener}, 2_000
    assert Task.yield(task, 5_100) == nil
    send(opener, :open)
    assert {:ok, server} = Task.await(task)
    assert %{agent: %{state: %{count: 0}}} = AgentServer.snapshot(server)
  end

  defp start_runtime do
    start_supervised!(
      {Jido, name: Runtime, namespace: "test/state-provider", persistence: {Jido.Persistence.ETS, table: Store}}
    )
  end

  defp signal(count), do: Jido.Signal.new!("count.set", %{count: count}, source: "/counter")
end
