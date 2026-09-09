defmodule JidoTest.Persistence.PluginIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Agent
  alias Jido.Persistence
  alias Jido.Persistence.ETS

  defmodule AgentFacet do
    use Jido.Agent.Plugin

    def state_spec(_opts), do: {:owned, Zoi.integer() |> Zoi.default(0)}
  end

  defmodule PersistenceFacet do
    use Jido.Persistence.Plugin

    def dump(value, context, opts) do
      notify(opts, {:dump, value, context})
      {:ok, Keyword.fetch!(opts, :prefix) <> Integer.to_string(value)}
    end

    def load(value, context, opts) do
      notify(opts, {:load, value, context})
      prefix = Keyword.fetch!(opts, :prefix)
      {number, ""} = value |> String.replace_prefix(prefix, "") |> Integer.parse()
      {:ok, number}
    end

    defp notify(opts, message) do
      if observer = Keyword.get(opts, :observer), do: send(observer, message)
    end
  end

  defmodule Package do
    use Jido.Plugin,
      agent: AgentFacet,
      persistence: PersistenceFacet,
      vsn: 4,
      option_keys: [agent: [], persistence: [:prefix, :observer]]
  end

  defmodule CustomCheckpointAgent do
    use Jido.Agent,
      name: "persistence_custom_checkpoint",
      vsn: 2,
      schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)}),
      plugins: [{Package, prefix: "sealed:"}]

    @impl Jido.Agent
    def checkpoint(agent, _context), do: {:ok, %{id: agent.id, complete: agent.state}}

    @impl Jido.Agent
    def restore(%{id: id, complete: state}, _context), do: new(id: id, state: state)
  end

  setup do
    Process.register(self(), __MODULE__.Observer)

    {:ok, persistence: {ETS, table: :"plugin_persistence_#{System.unique_integer([:positive])}"}}
  end

  test "the Persistence facet converts only its paired owned state", c do
    options = [prefix: "sealed:", observer: __MODULE__.Observer]

    agent =
      Agent.new!(
        name: "persistence_plugin_integration",
        schema: Zoi.object(%{visible: Zoi.integer() |> Zoi.default(1)}),
        plugins: [{Package, options}]
      )
      |> Agent.instantiate!(id: "owned-state", state: %{visible: 8, owned: 12})

    assert :ok = Persistence.save_agent(c.persistence, agent, revision: 3, reason: :test)
    assert_receive {:dump, 12, dump_context}
    assert dump_context.plugin == Package
    assert dump_context.plugin_vsn == 4
    assert dump_context.record_format == 2
    assert dump_context.direction == :dump
    assert dump_context.reason == :test

    {ETS, opts} = c.persistence
    key = Persistence.agent_key(nil, Agent, agent.id)
    assert {:ok, bytes} = ETS.get(key, opts)
    record = :erlang.binary_to_term(bytes, [:safe])
    assert record.checkpoint.state.visible == 8
    assert record.checkpoint.state.owned == "sealed:12"
    refute Map.has_key?(record.checkpoint.state, :adapter)

    assert {:ok, restored} = Persistence.load_agent(c.persistence, Agent, agent.id)
    assert_receive {:load, "sealed:12", load_context}
    assert load_context.direction == :load
    assert load_context.reason == :restore
    assert restored == agent
  end

  test "complete custom checkpoints bypass Plugin slice conversion", c do
    agent =
      CustomCheckpointAgent.new!(
        id: "custom-checkpoint",
        state: %{value: 7, owned: 9}
      )

    assert :ok = Persistence.save_agent(c.persistence, agent, revision: 2)

    {ETS, opts} = c.persistence
    key = Persistence.agent_key(nil, CustomCheckpointAgent, agent.id)
    assert {:ok, bytes} = ETS.get(key, opts)

    assert %{checkpoint: %{kind: :agent_custom, payload: payload}} =
             :erlang.binary_to_term(bytes, [:safe])

    assert payload == %{id: agent.id, complete: %{value: 7, owned: 9}}
    assert {:ok, ^agent} = Persistence.load_agent(c.persistence, CustomCheckpointAgent, agent.id)
  end
end
