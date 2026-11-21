defmodule Jido.AgentServer.StateProviderTest do
  use Covenant.Case, component: "jido.agent_server", async: false

  alias Jido.AgentServer
  alias Jido.Persistence.StateSource.Source

  defmodule StoreAdapter do
    @behaviour Jido.Persistence.Store
    @behaviour Jido.Persistence.TurnTransaction

    @impl true
    defdelegate validate_options(opts), to: Jido.Persistence.ETS
    @impl true
    defdelegate get(key, opts), to: Jido.Persistence.ETS
    @impl true
    defdelegate compare_and_swap(key, current, value, opts), to: Jido.Persistence.ETS
    @impl true
    defdelegate delete(key, opts), to: Jido.Persistence.ETS

    @impl true
    def transact(_config, _binding, operation), do: operation.(:test)
  end

  defmodule Provider do
    use Jido.Plugin
    @behaviour Jido.Persistence.StateSource

    @impl true
    def state_source(:count, _env) do
      {Jido.Joi.object(%{count: Jido.Joi.integer()}), :count}
    end

    @impl true
    def open(:count, %{forge_activation: true}, :restore, agent, _open), do: {:ok, agent, 1, 1, nil, %{}}
    def open(:count, %{projection: projection}, :create, _agent, open), do: open.(projection)
    def open(:count, %{projection: projection}, :restore, _agent, open), do: open.(fn _, _ -> {:ok, projection} end)
    def open(:count, _context, :create, _agent, open), do: open.(%{})
    def open(:count, _context, :restore, _agent, open), do: open.(fn _, _ -> {:ok, %{}} end)

    @impl true
    def refresh(:count, %{projection: projection}, _agent), do: {:ok, projection}
    def refresh(:count, _context, _agent), do: {:ok, %{}}

    @impl true
    def apply_state(:count, _context, _before, %{state: %{count: 3}}, :test),
      do: {:error, {:rejected, :not_allowed}}

    def apply_state(:count, _context, _before, %{state: %{count: 6}}, :test) do
      notify = fn ->
        send(Process.whereis(Jido.AgentServer.StateProviderTest), {:saved, self()})

        receive do
          :complete -> :ok
        end
      end

      {:ok, %{count: 6}, notify}
    end

    def apply_state(:count, _context, _before, candidate, :test) do
      {:ok, %{count: candidate.state.count * 2}, nil}
    end
  end

  defmodule RowProvider do
    use Jido.Plugin
    @behaviour Jido.Persistence.StateSource

    @impl true
    defdelegate state_source(option, env), to: Provider

    @impl true
    def startup_id(:count, id) when is_binary(id), do: {:ok, id}
    def startup_id(:count, _), do: {:error, :row_id_required}

    @impl true
    def open(:count, _context, :create, %{id: "slow"}, open) do
      send(Process.whereis(Jido.AgentServer.StateProviderTest), {:opening, self()})

      receive do
        :open -> open.(%{count: 0})
      end
    end

    def open(:count, _context, :create, _agent, open), do: open.(%{count: 0})
    def open(:count, _context, :restore, _agent, open), do: open.(fn _, _ -> {:ok, %{}} end)

    @impl true
    defdelegate refresh(option, context, agent), to: Provider

    @impl true
    defdelegate apply_state(option, context, before, candidate, tx), to: Provider
  end

  defmodule RowCounter do
    use Jido.Agent, name: "row_counter", plugins: [RowProvider]

    state do
      state_source(RowProvider, :count)
    end
  end

  defmodule SetCount do
    use Jido.Action, name: "provider_set_count", schema: Jido.Joi.object(%{count: Jido.Joi.integer()})

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule Counter do
    use Jido.Agent, name: "provider_counter", plugins: [Provider]

    state do
      state_source(Provider, :count)
    end

    routes do
      route "count.set", SetCount
    end
  end

  @tag obligation: "jido.agent_server.I109"
  test "create, restore and refresh reject fields outside the source schema" do
    alias Jido.Persistence.StateSource

    agent = Counter.instantiate!(id: "projected", state: %{count: 0})
    persistence = %Jido.Persistence.Config{store: {StoreAdapter, []}, codec: Jido.Persistence.Codec.Term}
    context = %{persistence: persistence, projection: %{foreign: 1}}
    reason = {:state_source_undeclared_fields, [:foreign]}

    assert {:error, ^reason} =
             StateSource.open(%{agent | state: nil}, context, :create, fn _ ->
               flunk("An invalid projection reached checkpoint creation")
             end)

    assert {:error, ^reason} =
             StateSource.open(%{agent | state: nil}, context, :restore, fn _ ->
               {:ok, agent, 1, 1, nil, %{}}
             end)

    assert {:error, ^reason} = StateSource.refresh(agent, context)
    assert {:error, :invalid_provider_state} = StateSource.refresh(agent, %{context | projection: %{agent | id: "bad"}})

    assert {:error, :invalid_state_source_activation} =
             StateSource.open(%{agent | state: nil}, Map.put(context, :forge_activation, true), :restore, fn _ ->
               flunk("The provider bypassed checkpoint restoration")
             end)
  end

  @tag obligation: "jido.agent_server.I108"
  test "the provider commits canonical state and a rejected write leaves the agent usable" do
    start_supervised!(
      {Jido, name: Runtime, namespace: "test/state-provider", persistence: {StoreAdapter, table: Store}}
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
      {Jido, name: Runtime, namespace: "test/state-provider", persistence: {StoreAdapter, table: Store}}
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
      %{{"test/agent", 1} => RowCounter, {"test/schema", 1} => schema, {RowProvider.id(), 1} => RowProvider}
    end

    registry = Jido.Catalog.from_targets!(__MODULE__, :jido, targets.(definition.schema))
    opts = fn catalog -> [catalog: catalog, codec: Jido.Agent.Codec] end
    assert {:ok, json} = Jido.Codec.encode_json(definition, opts.(registry))
    assert {:ok, ^definition} = Jido.Codec.decode_json(json, opts.(registry))

    without_plugin = json |> Jason.decode!() |> put_in(["definition", "plugins"], []) |> Jason.encode!()

    assert {:error, [%{code: :state_source_plugin_required, path: ["definition", "plugins"]}]} =
             Jido.Codec.decode_json(without_plugin, opts.(registry))

    alternate = Jido.Catalog.from_targets!(__MODULE__, :jido, targets.(Jido.Joi.object(%{count: Jido.Joi.any()})))

    assert {:error, [%{code: :state_provider_schema_mismatch, path: ["definition", "schema"]}]} =
             Jido.Codec.decode_json(json, opts.(alternate))
  end

  @tag obligation: "jido.agent_server.I109"
  test "addressed creation uses the row source and verifies its ID" do
    start_runtime()
    source = fn id -> %Source{provider: RowProvider, input: id} end

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
      persistence: {StoreAdapter, table: Store},
      agent_server: [persistence_timeout: 7_000]
    ]

    start_supervised!({Jido, options})
    source = %Source{provider: RowProvider, input: "slow"}
    task = Task.async(fn -> Jido.start_agent(Runtime, RowCounter, state: source) end)
    assert_receive {:opening, opener}, 2_000
    assert Task.yield(task, 5_100) == nil
    send(opener, :open)
    assert {:ok, server} = Task.await(task)
    assert %{agent: %{state: %{count: 0}}} = AgentServer.snapshot(server)
  end

  defp start_runtime do
    start_supervised!(
      {Jido, name: Runtime, namespace: "test/state-provider", persistence: {StoreAdapter, table: Store}}
    )
  end

  defp signal(count), do: Jido.Signal.new!("count.set", %{count: count}, source: "/counter")
end
