defmodule Jido.AuthoringIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Authoring.Registry

  defmodule Extension do
    use Jido.Agent.Extension, id: "tests/extensions/sample", vsn: 2
  end

  defmodule Plugin do
    use Jido.Plugin, id: "tests/plugins/sample", vsn: 3
    def state_spec(_opts), do: :none
  end

  defmodule Agent do
    use Jido.Agent, id: "tests/agents/sample", name: "sample_agent"
  end

  defmodule Vocabulary do
    def __jido_authoring__ do
      %{
        id: "tests/schemas/sample-agent",
        kind: :schema,
        vsn: 1,
        target: Agent.definition().schema
      }
    end
  end

  setup do
    registry = :persistent_term.get({Jido.Discovery, :registry}, :not_initialized)

    on_exit(fn ->
      if registry == :not_initialized,
        do: :persistent_term.erase({Jido.Discovery, :registry}),
        else: :persistent_term.put({Jido.Discovery, :registry}, registry)
    end)
  end

  test "Agent extensions and Plugins use the shared Authoring Registry" do
    assert :ok =
             Jido.Discovery.refresh(
               applications: [],
               modules: [Agent, Extension, Plugin, Vocabulary, Jido.Agent.Codec]
             )

    registry = Jido.Discovery.registry()

    assert %{kind: :agent, target: Agent} =
             Registry.get(registry, "tests/agents/sample", 1)

    assert %{kind: :extension, target: Extension} =
             Registry.get(registry, "tests/extensions/sample", 2)

    assert %{kind: :plugin, target: Plugin} =
             Registry.get(registry, "tests/plugins/sample", 3)

    assert Registry.codec(registry, "jido.agent.definition", 1) ==
             {:ok, Jido.Agent.Codec}

    definition = Agent.definition()
    assert {:ok, document} = Jido.Authoring.encode(definition, registry: registry)
    assert document["vsn"] == 1
    assert {:ok, ^definition} = Jido.Authoring.decode(document, registry: registry)
  end

  test "the default scan includes core Jido when it is loaded" do
    assert :ok = Jido.Discovery.refresh()

    assert Registry.codec(Jido.Discovery.registry(), "jido.agent.definition", 1) ==
             {:ok, Jido.Agent.Codec}
  end

  test "legacy Agent and Plugin authoring facades are not exported" do
    refute function_exported?(Jido.Agent, :to_json, 2)
    refute function_exported?(Jido.Agent, :from_json, 2)
    refute function_exported?(Jido.Agent.Codec, :encode, 2)
    refute function_exported?(Jido.Agent.Codec, :decode, 2)
    refute function_exported?(Jido.Agent.Codec, :from_json, 2)
    refute function_exported?(Jido.Plugin, :manifest, 1)
  end
end
