defmodule JidoTest.Persistence.LiveStateTest do
  use JidoTest.Case, async: true

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias Jido.Persistence
  alias Jido.Persistence.ETS

  defmodule Update do
    use Jido.Action, name: "local_state_update"

    def run(input, context) do
      state = %{
        context.agent_state
        | payload: input.payload,
          count: context.agent_state.count + 1
      }

      effect =
        Jido.Agent.Directive.emit_to_pid(
          Jido.Signal.new!("local.updated", %{}, source: "/test"),
          input.observer
        )

      {:ok, state, [effect]}
    end
  end

  defmodule LocalAgent do
    use Jido.Agent, name: "local_state_agent"

    agent do
      schema Zoi.object(%{
               payload: Zoi.any() |> Zoi.default(<<>>),
               count: Zoi.integer() |> Zoi.default(0)
             })
    end

    routes do
      route "local.update", Update
    end
  end

  defmodule CustomAgent do
    use Jido.Agent, name: "local_custom_checkpoint"

    agent do
      schema Zoi.object(%{
               payload: Zoi.any() |> Zoi.default(<<>>),
               count: Zoi.integer() |> Zoi.default(0)
             })
    end

    routes do
      route "local.update", Update
    end

    def checkpoint(agent, _context) do
      case agent.state.payload do
        :invalid_dump ->
          {:ok, %{value: self()}}

        :dump_failure ->
          {:error, :conversion_failed}

        bits ->
          {:ok, %{id: agent.id, bits: for(<<bit::1 <- bits>>, do: bit), count: agent.state.count}}
      end
    end

    def restore(payload, _context) do
      bits = for bit <- payload.bits, into: <<>>, do: <<bit::1>>
      agent = new!(id: payload.id, state: %{payload: bits})
      {:ok, %{agent | state: %{agent.state | count: payload.count}}}
    end
  end

  defmodule OwnedFacet do
    use Jido.Agent.Plugin

    def state_spec(_opts),
      do: {:owned, Zoi.object(%{bits: Zoi.any()}) |> Zoi.default(%{bits: <<>>})}

    def reduce(reduction, _opts),
      do: {:ok, Map.get(reduction.signal.data, :owned, reduction.plugin_state)}
  end

  defmodule StoredFacet do
    use Jido.Persistence.Plugin

    def dump(%{bits: :invalid_dump}, _context, _opts), do: {:ok, %{bits: <<5::3>>}}
    def dump(%{bits: :dump_failure}, _context, _opts), do: {:error, :conversion_failed}
    def dump(%{bits: bits}, _context, _opts), do: {:ok, for(<<bit::1 <- bits>>, do: bit)}

    def load(:invalid_state, _context, _opts), do: {:ok, :invalid_state}

    def load(bits, _context, _opts),
      do: {:ok, %{bits: for(bit <- bits, into: <<>>, do: <<bit::1>>)}}
  end

  defmodule Package do
    use Jido.Plugin, agent: OwnedFacet, persistence: StoredFacet
  end

  defmodule PluginAgent do
    use Jido.Agent, name: "local_plugin_checkpoint"

    agent do
      schema Zoi.object(%{
               payload: Zoi.any() |> Zoi.default(<<>>),
               count: Zoi.integer() |> Zoi.default(0)
             })

      plugin Package
    end

    routes do
      route "local.update", Update
    end
  end

  defmodule RejectedStorage do
    @behaviour Jido.Persistence.Adapter
    defdelegate validate_options(opts), to: ETS
    defdelegate get(key, opts), to: ETS
    defdelegate put(key, value, opts), to: ETS
    defdelegate delete(key, opts), to: ETS

    def compare_and_swap(key, expected, value, opts) do
      if :erlang.binary_to_term(value, [:safe]).revision == 0,
        do: ETS.compare_and_swap(key, expected, value, opts),
        else: {:error, {:rejected, :storage_unavailable}}
    end
  end

  setup do
    {:ok, persistence: {ETS, table: :"local_state_#{System.unique_integer([:positive])}"}}
  end

  test "custom conversion saves and restores a non-byte-aligned value", c do
    agent = CustomAgent.new!(id: unique_id(), state: %{payload: <<5::3>>, count: 2})
    assert {:ok, checkpoint} = Agent.checkpoint(agent)
    assert checkpoint.payload.bits == [1, 0, 1]
    assert {:ok, ^agent} = Agent.restore(CustomAgent, checkpoint)
    assert :ok = Persistence.save_agent(c.persistence, agent, instance: c.jido)

    assert {:ok, ^agent} =
             Persistence.load_agent(c.persistence, CustomAgent, agent.id, instance: c.jido)
  end

  test "custom output and restored schema and identity remain strict", c do
    agent = CustomAgent.new!(id: unique_id(), state: %{payload: <<5::3>>})
    assert :ok = Persistence.save_agent(c.persistence, agent, instance: c.jido)
    record = record(c, agent.id)

    for {field, value} <- [id: "different", count: :invalid, bits: self()] do
      changed = put_in(record, [:checkpoint, :payload, field], value)
      put_record(c, agent.id, changed)

      assert {:error, _reason} =
               Persistence.load_agent(c.persistence, CustomAgent, agent.id, instance: c.jido)
    end

    for changed <- [
          put_in(record, [:checkpoint, :vsn], 99),
          put_in(record, [:checkpoint, :agent_module], LocalAgent)
        ] do
      put_record(c, agent.id, changed)

      assert {:error, _reason} =
               Persistence.load_agent(c.persistence, CustomAgent, agent.id, instance: c.jido)
    end

    invalid = %{agent | state: %{agent.state | payload: :invalid_dump}}

    assert {:error,
            %{details: %{code: :non_portable_term, path: [:checkpoint, :payload, :value]}}} =
             Persistence.save_agent(c.persistence, invalid, instance: c.jido)
  end

  test "Plugin conversion handles local owned state for generated and embedded definitions", c do
    for definition <- [
          PluginAgent.definition(),
          Agent.new!(name: "embedded_local_plugin", plugins: [Package]),
          Agent.new!(name: "embedded_generated_plugin", module: PluginAgent, plugins: [Package])
        ] do
      agent = Agent.instantiate!(definition, id: unique_id(), state: %{owned: %{bits: <<5::3>>}})
      assert {:error, %{details: %{code: :non_portable_term}}} = Agent.checkpoint(agent)
      assert :ok = Persistence.save_agent(c.persistence, agent, instance: c.jido)
      assert record(c, agent.id).checkpoint.state.owned == [1, 0, 1]

      assert {:ok, ^agent} =
               Persistence.load_agent(c.persistence, agent.module, agent.id, instance: c.jido)
    end
  end

  test "Plugin conversion cannot hide invalid stored records or invalid restored owned state",
       c do
    agent = PluginAgent.new!(id: unique_id(), state: %{owned: %{bits: <<5::3>>}})
    assert :ok = Persistence.save_agent(c.persistence, agent, instance: c.jido)
    record = record(c, agent.id)

    for value <- [self(), <<5::3>>, :invalid_state] do
      put_record(c, agent.id, put_in(record, [:checkpoint, :state, :owned], value))

      assert {:error, _reason} =
               Persistence.load_agent(c.persistence, PluginAgent, agent.id, instance: c.jido)
    end

    for changed <- [
          put_in(record, [:checkpoint, :id], "different"),
          put_in(record, [:checkpoint, :vsn], 99)
        ] do
      put_record(c, agent.id, changed)

      assert {:error, _reason} =
               Persistence.load_agent(c.persistence, PluginAgent, agent.id, instance: c.jido)
    end
  end

  test "live execution commits local domain and Plugin values without persistence", c do
    initial = PluginAgent.new!(state: %{payload: self(), owned: %{bits: <<5::3>>}})
    assert {:ok, server} = Jido.start_agent(c.jido, initial)
    port = Port.open({:spawn_executable, System.find_executable("true")}, [])
    on_exit(fn -> if Port.info(port), do: Port.close(port) end)

    for value <- [self(), port, make_ref(), fn -> :local end, [1 | :tail], <<5::3>>] do
      input = %{payload: value, observer: self(), owned: %{bits: value}}
      assert {:ok, candidate, [_effect]} = Agent.cmd(initial, signal("local.update", input))
      assert candidate.state.owned.bits === value
      assert {:ok, committed} = Server.call(server, signal("local.update", input))
      assert committed.state.payload === value
      assert committed.state.owned.bits === value
      assert_receive {:signal, %{type: "local.updated"}}, 1_000
      assert Server.agent(server) == committed
    end

    assert {:error, _reason} =
             Server.call(
               server,
               signal("local.update", %{payload: :valid, observer: self(), owned: :invalid})
             )

    assert Server.agent(server).state.count == 6
  end

  test "persistent custom and Plugin commits convert before storage and dispatch", c do
    for {module, input} <- [
          {CustomAgent, %{payload: <<5::3>>}},
          {PluginAgent, %{payload: :portable, owned: %{bits: <<5::3>>}}}
        ] do
      assert {:ok, server} =
               Jido.start_agent(c.jido, module, persistence: c.persistence, restart: :temporary)

      assert {:ok, committed} =
               Server.call(server, signal("local.update", Map.put(input, :observer, self())))

      assert_receive {:signal, %{type: "local.updated"}}, 1_000

      assert {:ok, ^committed, 1} =
               Persistence.load_agent_with_revision(c.persistence, module, committed.id,
                 instance: c.jido
               )
    end
  end

  test "checkpoint, conversion, and storage failures neither commit nor dispatch", c do
    cases = [
      {LocalAgent, ETS, %{payload: <<5::3>>}},
      {CustomAgent, ETS, %{payload: :invalid_dump}},
      {CustomAgent, ETS, %{payload: :dump_failure}},
      {PluginAgent, ETS, %{payload: :portable, owned: %{bits: :invalid_dump}}},
      {PluginAgent, ETS, %{payload: :portable, owned: %{bits: :dump_failure}}},
      {PluginAgent, ETS, %{payload: <<5::3>>, owned: %{bits: <<5::3>>}}},
      {CustomAgent, RejectedStorage, %{payload: <<5::3>>}},
      {PluginAgent, RejectedStorage, %{payload: :portable, owned: %{bits: <<5::3>>}}}
    ]

    for {module, adapter, input} <- cases do
      persistence = {adapter, elem(c.persistence, 1)}

      assert {:ok, server} =
               Jido.start_agent(c.jido, module, persistence: persistence, restart: :temporary)

      before = Server.snapshot(server)
      monitor = Process.monitor(server)

      assert {:error, {:persistence_failed, _reason}} =
               Server.call(server, signal("local.update", Map.put(input, :observer, self())))

      assert_receive {:DOWN, ^monitor, :process, ^server, _reason}, 1_000

      assert {:ok, saved, 0} =
               Persistence.load_agent_with_revision(persistence, module, before.agent.id,
                 instance: c.jido
               )

      assert saved == before.agent
      refute_received {:signal, %{type: "local.updated"}}
    end
  end

  defp record(c, id) do
    {ETS, opts} = c.persistence
    assert {:ok, bytes} = ETS.get(key(c, id), opts)
    :erlang.binary_to_term(bytes, [:safe])
  end

  defp put_record(c, id, record) do
    {ETS, opts} = c.persistence
    assert :ok = ETS.put(key(c, id), :erlang.term_to_binary(record), opts)
  end

  defp key(c, id),
    do: Persistence.agent_key(Jido.Agent.Ref.new!(namespace: Jido.namespace(c.jido), id: id))
end
