defmodule JidoTest.Examples.Basic.AgentExtensionTest do
  use ExUnit.Case, async: true
  @moduletag :example

  alias Jido.Agent
  alias Jido.Examples.AgentExtension
  alias Jido.Examples.AgentExtension.Labels

  test "DSL and Map authoring produce the same static contribution" do
    definition = AgentExtension.Agent.definition()
    entry = %{id: "examples.labels", provider: Labels, vsn: 1, data: %{owner: "examples"}}

    assert definition.extensions == [entry]
    assert definition.metadata == %{}
    assert Labels.runtime_support() == :none
    assert Agent.runtime_plugins(definition) == []

    assert {:ok, from_map} = Agent.define(%{name: "map_labels", extensions: [entry]})
    assert from_map.extensions == definition.extensions
  end

  test "pure execution preserves the contribution while updating Agent state" do
    instance = AgentExtension.Agent.instantiate!(id: "agent-extension")
    assert {:ok, signal} = AgentExtension.Agent.add_signal(%{amount: 3})

    assert {:ok, result, []} = Agent.cmd(instance, signal)
    assert result.state == %{count: 3}
    assert instance.state == %{count: 0}
    assert result.extensions == instance.extensions
    assert result.metadata == %{}
  end

  test "Map authoring rejects invalid contribution data and versions" do
    entry = %{id: "examples.labels", provider: Labels, vsn: 1, data: %{owner: "examples"}}

    for invalid <- [
          %{entry | data: %{owner: ""}},
          %{entry | data: %{owner: 42}},
          %{entry | data: %{owner: "examples", unknown: true}},
          %{entry | vsn: 2}
        ] do
      assert {:error, %Agent.Error{path: [:extensions | _]}} =
               Agent.define(%{name: "invalid_labels", extensions: [invalid]})
    end
  end
end
