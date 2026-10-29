defmodule JidoTest.Persistence.PluginIntegrationTest do
  use Covenant.Case, component: "jido.persistence", async: false

  alias Jido.Agent
  alias Jido.Persistence
  alias Jido.Persistence.ETS
  alias Jido.Persistence.Plugin, as: PersistencePlugin

  defmodule AgentFacet do
    @behaviour Jido.Plugin

    def state_spec(_opts), do: {:owned, Zoi.integer() |> Zoi.default(0)}
  end

  defmodule PersistenceFacet do
    @behaviour Jido.Plugin

    def dump(value, context, opts) do
      notify(opts, {:dump, value, context})

      case Process.get({__MODULE__, :dump_fault}) do
        :raise -> raise "dump callback failed"
        :wrong_return -> :invalid
        :non_portable -> {:ok, self()}
        _ -> {:ok, Keyword.fetch!(opts, :prefix) <> Integer.to_string(value)}
      end
    end

    def load(value, context, opts) do
      notify(opts, {:load, value, context})

      case Process.get({__MODULE__, :load_fault}) do
        :raise ->
          raise "load callback failed"

        :wrong_return ->
          :invalid

        :non_portable ->
          {:ok, self()}

        :invalid_state ->
          {:ok, "not an integer"}

        _ ->
          prefix = Keyword.fetch!(opts, :prefix)
          {number, ""} = value |> String.replace_prefix(prefix, "") |> Integer.parse()
          {:ok, number}
      end
    end

    defp notify(opts, message) do
      if observer = Keyword.get(opts, :observer), do: send(observer, message)
    end
  end

  defmodule Package do
    use Jido.Plugin, vsn: 4, option_keys: [agent: [], persistence: [:prefix, :observer]]

    @impl true
    defdelegate state_spec(opts), to: JidoTest.Persistence.PluginIntegrationTest.AgentFacet

    @impl true
    defdelegate dump(value, context, opts),
      to: JidoTest.Persistence.PluginIntegrationTest.PersistenceFacet

    @impl true
    defdelegate load(value, context, opts),
      to: JidoTest.Persistence.PluginIntegrationTest.PersistenceFacet
  end

  defmodule CustomCheckpointAgent do
    use Jido.Agent,
      name: "persistence_custom_checkpoint",
      vsn: 2,
      plugins: [{Package, %{prefix: "sealed:"}}]

    state do
      schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
    end

    @impl Jido.Agent
    def checkpoint(agent, _context), do: {:ok, %{id: agent.id, complete: agent.state}}

    @impl Jido.Agent
    def restore(%{id: id, complete: state}, _context), do: instantiate(id: id, state: state)
  end

  defmodule StoredStatePackage do
    use Jido.Plugin

    @impl true
    def state_spec(_opts) do
      {:owned,
       Zoi.object(
         %{
           count: Zoi.integer() |> Zoi.nullable() |> Zoi.default(3),
           optional: Zoi.integer() |> Zoi.default(7) |> Zoi.optional()
         },
         empty_values: [nil]
       )
       |> Zoi.default(%{})}
    end

    @impl true
    def dump(value, _context, _opts), do: {:ok, value}

    @impl true
    def load(value, _context, _opts), do: {:ok, Process.get({__MODULE__, :loaded}, value)}
  end

  setup do
    Process.register(self(), __MODULE__.Observer)

    {:ok, persistence: {ETS, table: :"plugin_persistence_#{System.unique_integer([:positive])}"}}
  end

  @tag obligation: "jido.persistence.I10"
  test "the Persistence facet converts only its paired owned state", c do
    options = [prefix: "sealed:", observer: __MODULE__.Observer]

    agent =
      Agent.define!(%{
        name: "persistence_plugin_integration",
        schema: Zoi.object(%{visible: Zoi.integer() |> Zoi.default(1)}),
        plugins: [
          %{id: Package.id(), provider: Package, vsn: Package.vsn(), data: Map.new(options)}
        ]
      })
      |> Agent.instantiate!(id: "owned-state", state: %{visible: 8, owned: 12})

    assert :ok =
             Persistence.save_agent(c.persistence, agent,
               namespace: "persistence-test",
               revision: 3,
               reason: :test
             )

    assert_receive {:dump, 12, dump_context}
    assert dump_context.plugin == Package
    assert dump_context.plugin_vsn == 4
    assert dump_context.record_format == 1
    assert dump_context.direction == :dump
    assert dump_context.reason == :test

    {ETS, opts} = c.persistence
    key = Persistence.agent_key(Jido.Agent.Ref.new!(namespace: "persistence-test", id: agent.id))
    assert {:ok, bytes} = ETS.get(key, opts)
    record = :erlang.binary_to_term(bytes, [:safe])
    assert record.checkpoint.agent.state.visible == 8
    assert record.checkpoint.agent.state.owned == "sealed:12"
    refute Map.has_key?(record.checkpoint.agent.state, :adapter)

    assert {:ok, restored} =
             Persistence.load_agent(c.persistence, agent.module, agent.id,
               namespace: "persistence-test"
             )

    assert_receive {:load, "sealed:12", load_context}
    assert load_context.direction == :load
    assert load_context.reason == :restore
    assert restored == agent
  end

  @tag obligation: "jido.persistence.I10"
  test "Plugin conversion context is exact and bound to its owner" do
    options = [prefix: "sealed:"]
    assert {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([{Package, options}])

    dump_context = PersistencePlugin.context(spec, :dump, 1, :contract)

    assert %Jido.Persistence.Plugin.Context{
             plugin: Package,
             plugin_vsn: 4,
             record_format: 1,
             direction: :dump,
             reason: :contract
           } = dump_context

    assert {:ok, "sealed:3"} = PersistencePlugin.dump(spec, 3, dump_context)

    assert %Jido.Persistence.Plugin.Context{record_format: 1} =
             PersistencePlugin.context(spec, :dump, 1, :contract)

    for changed <- [
          %{dump_context | plugin: String},
          %{dump_context | plugin_vsn: 5}
        ] do
      assert {:error,
              %Jido.Error.ValidationError{
                details: %{
                  plugin: Package,
                  facet: Package,
                  direction: :dump,
                  context: ^changed
                }
              }} = PersistencePlugin.dump(spec, 3, changed)
    end

    load_context = %{dump_context | direction: :load}

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{direction: :dump, context: ^load_context}
            }} = PersistencePlugin.dump(spec, 3, load_context)

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{direction: :load, context: ^dump_context}
            }} = PersistencePlugin.load(spec, "sealed:3", dump_context)

    assert {:error,
            %Jido.Error.ExecutionError{
              details: %{
                callback: :load,
                path: [:plugin_state, Package],
                plugin: Package
              }
            }} = PersistencePlugin.load(spec, self(), load_context)

    for {direction, record_format} <- [{:other, 4}, {:dump, 0}, {:dump, -1}] do
      assert_raise FunctionClauseError, fn ->
        PersistencePlugin.context(spec, direction, record_format, :contract)
      end
    end
  end

  @tag obligation: "jido.persistence.I11"
  test "complete custom checkpoints bypass Plugin slice conversion", c do
    agent =
      CustomCheckpointAgent.instantiate!(
        id: "custom-checkpoint",
        state: %{value: 7, owned: 9}
      )

    assert :ok =
             Persistence.save_agent(c.persistence, agent,
               namespace: "persistence-test",
               revision: 2
             )

    {ETS, opts} = c.persistence
    key = Persistence.agent_key(Jido.Agent.Ref.new!(namespace: "persistence-test", id: agent.id))
    assert {:ok, bytes} = ETS.get(key, opts)

    assert %{checkpoint: %{state_format: :custom, agent: %{state: payload}}} =
             :erlang.binary_to_term(bytes, [:safe])

    assert payload == %{id: agent.id, complete: %{value: 7, owned: 9}}

    assert {:ok, ^agent} =
             Persistence.load_agent(c.persistence, CustomCheckpointAgent, agent.id,
               namespace: "persistence-test"
             )
  end

  @tag obligation: ["jido.persistence.I9", "jido.persistence.I11"]
  test "dump callback faults and invalid values cannot write a record", c do
    for {fault, code, expected_details} <- [
          {:raise, :plugin_callback_failed, %{callback: :dump, plugin: Package}},
          {:wrong_return, :plugin_invalid_callback_result,
           %{callback: :dump, plugin: Package, result: :invalid}},
          {:non_portable, :non_portable_term,
           %{callback: :dump, path: [:plugin_state, Package], plugin: Package}}
        ] do
      agent = owned_agent("dump-#{fault}")

      key =
        Persistence.agent_key(Jido.Agent.Ref.new!(namespace: "persistence-test", id: agent.id))

      {ETS, opts} = c.persistence
      Process.put({PersistenceFacet, :dump_fault}, fault)

      assert {:error, error} =
               Persistence.save_agent(c.persistence, agent, namespace: "persistence-test")

      assert Jido.Error.code(error) == code
      assert Map.take(error.details, Map.keys(expected_details)) == expected_details

      assert {:error, :not_found} = ETS.get(key, opts)
    end

    Process.delete({PersistenceFacet, :dump_fault})
  end

  @tag obligation: ["jido.persistence.I10", "jido.persistence.I11"]
  test "load callback faults and invalid values cannot restore an Agent", c do
    for {fault, code, expected_details} <- [
          {:raise, :plugin_callback_failed, %{callback: :load, plugin: Package}},
          {:wrong_return, :plugin_invalid_callback_result,
           %{callback: :load, plugin: Package, result: :invalid}},
          {:non_portable, :plugin_invalid_callback_result, %{plugin: Package}},
          {:invalid_state, :plugin_invalid_callback_result, %{plugin: Package}}
        ] do
      agent = owned_agent("load-#{fault}")
      assert :ok = Persistence.save_agent(c.persistence, agent, namespace: "persistence-test")
      Process.put({PersistenceFacet, :load_fault}, fault)

      assert {:error, error} =
               Persistence.load_agent(c.persistence, agent.module, agent.id,
                 namespace: "persistence-test"
               )

      assert Jido.Error.code(error) == code
      assert Map.take(error.details, Map.keys(expected_details)) == expected_details

      if fault in [:non_portable, :invalid_state],
        do: assert(Map.has_key?(error.details, :errors))

      Process.delete({PersistenceFacet, :load_fault})

      assert {:ok, ^agent} =
               Persistence.load_agent(c.persistence, agent.module, agent.id,
                 namespace: "persistence-test"
               )
    end
  end

  @tag obligation: ["jido.persistence.I10", "jido.persistence.I11"]
  test "a missing Plugin-owned field cannot write a record", c do
    agent = owned_agent("missing-owned")
    incomplete = %{agent | state: Map.delete(agent.state, :owned)}
    key = Persistence.agent_key(Jido.Agent.Ref.new!(namespace: "persistence-test", id: agent.id))
    {ETS, opts} = c.persistence

    assert {:error, %Jido.Agent.Error{code: :incomplete_state, path: [:state]}} =
             Persistence.save_agent(c.persistence, incomplete, namespace: "persistence-test")

    assert {:error, :not_found} = ETS.get(key, opts)

    assert :ok = Persistence.save_agent(c.persistence, agent, namespace: "persistence-test")
    assert {:ok, bytes} = ETS.get(key, opts)
    record = :erlang.binary_to_term(bytes, [:safe])
    stored = update_in(record.checkpoint.agent.state, &Map.delete(&1, :owned))
    assert :ok = ETS.put(key, :erlang.term_to_binary(stored), opts)

    assert {:error, {:invalid_persistence_record, :plugin_state}} =
             Persistence.load_agent(c.persistence, agent.module, agent.id,
               namespace: "persistence-test"
             )
  end

  @tag obligation: "jido.persistence.I10"
  test "Plugin load preserves nullable values and absent optional fields", c do
    agent =
      Agent.define!(%{
        name: "stored_plugin_state",
        plugins: [
          %{
            id: StoredStatePackage.id(),
            provider: StoredStatePackage,
            vsn: StoredStatePackage.vsn(),
            data: %{}
          }
        ]
      })
      |> Agent.instantiate!(id: "stored-plugin-state")

    assert {:ok, agent} = Agent.transition(agent, %{owned: %{count: nil}})
    assert :ok = Persistence.save_agent(c.persistence, agent, namespace: "persistence-test")

    assert {:ok, ^agent} =
             Persistence.load_agent(c.persistence, agent.module, agent.id,
               namespace: "persistence-test"
             )
  end

  @tag obligation: ["jido.persistence.I10", "jido.persistence.I11"]
  test "Plugin load rejects incomplete or invalid stored output", c do
    agent =
      Agent.define!(%{
        name: "invalid_loaded_state",
        plugins: [
          %{
            id: StoredStatePackage.id(),
            provider: StoredStatePackage,
            vsn: StoredStatePackage.vsn(),
            data: %{}
          }
        ]
      })
      |> Agent.instantiate!(id: "invalid-loaded-state")

    assert :ok = Persistence.save_agent(c.persistence, agent, namespace: "persistence-test")

    for loaded <- [%{}, %{count: "invalid"}] do
      Process.put({StoredStatePackage, :loaded}, loaded)

      assert {:error, error} =
               Persistence.load_agent(c.persistence, agent.module, agent.id,
                 namespace: "persistence-test"
               )

      assert Jido.Error.code(error) == :plugin_invalid_callback_result
    end

    Process.delete({StoredStatePackage, :loaded})

    assert {:ok, ^agent} =
             Persistence.load_agent(c.persistence, agent.module, agent.id,
               namespace: "persistence-test"
             )
  end

  defp owned_agent(id) do
    Agent.define!(%{
      name: "persistence_plugin_faults",
      schema: Zoi.object(%{visible: Zoi.integer() |> Zoi.default(1)}),
      plugins: [
        %{id: Package.id(), provider: Package, vsn: Package.vsn(), data: %{prefix: "sealed:"}}
      ]
    })
    |> Agent.instantiate!(id: id, state: %{visible: 8, owned: 12})
  end
end
