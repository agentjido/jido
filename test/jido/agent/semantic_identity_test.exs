defmodule Jido.Agent.SemanticIdentityTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.{Plugin, PluginDefaults}

  defmodule SearchPlugin do
  end

  defmodule RouteMatches do
    def important?(_signal), do: true
  end

  test "semantic identity is deterministic and ignores all runtime fields" do
    definition =
      Agent.new!(
        name: "identity_agent",
        description: "Stable definition",
        plugins: [Plugin.new!(module: SearchPlugin, config: %{limit: 10})],
        routes: [
          {"support.received", &RouteMatches.important?/1, SearchPlugin}
        ],
        metadata: %{owner: "support"}
      )

    first_instance =
      %{definition | id: "one", state: %{count: 1}, agent_module: __MODULE__}

    second_instance =
      %{definition | id: "two", state: %{count: 2}, agent_module: SearchPlugin}

    assert {:ok, identity} = Agent.semantic_identity(definition)
    assert Agent.semantic_identity(first_instance) == {:ok, identity}
    assert Agent.semantic_identity(second_instance) == {:ok, identity}
    assert identity.version == 1
    assert identity.algorithm == :sha256
    assert identity.digest =~ ~r/^[0-9a-f]{64}$/

    assert identity.uuid =~
             ~r/^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
  end

  test "authored plugin-default policy changes semantic identity" do
    inherited = Agent.new!(name: "defaults_agent")

    disabled =
      Agent.new!(
        name: "defaults_agent",
        plugin_defaults: PluginDefaults.new!(mode: :none)
      )

    replaced =
      Agent.new!(
        name: "defaults_agent",
        plugin_defaults:
          PluginDefaults.new!(
            mode: :inherit,
            overrides: %{search: Plugin.new!(module: SearchPlugin)}
          )
      )

    identities =
      Enum.map([inherited, disabled, replaced], fn agent ->
        {:ok, identity} = Agent.semantic_identity(agent)
        identity.uuid
      end)

    assert Enum.uniq(identities) == identities
  end

  test "inspection uses only the neutral canonical definition" do
    definition = Agent.new!(name: "inspection_agent", metadata: %{source: "native"})
    instance = %{definition | id: "instance", state: %{secret: true}, agent_module: __MODULE__}

    assert Agent.to_map(instance) == Agent.to_map(definition)

    semantic_map = Agent.to_map(instance)
    refute Map.has_key?(semantic_map, :id)
    refute Map.has_key?(semantic_map, :state)
    refute Map.has_key?(semantic_map, :agent_module)

    assert {:ok, explanation} = Agent.explain(instance)
    assert explanation.kind == :agent
    assert explanation.version == 1
    assert explanation.lifecycle == :instance
    assert Map.take(explanation, Map.keys(semantic_map)) == semantic_map
    assert explanation.diagnostics.route_count == 0
    assert explanation.identity == elem(Agent.semantic_identity(definition), 1)
  end
end
