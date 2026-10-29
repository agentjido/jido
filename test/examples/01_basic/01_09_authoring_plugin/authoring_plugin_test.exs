defmodule JidoTest.Examples.Basic.AuthoringPluginTest do
  use ExUnit.Case, async: true
  @moduletag :example

  alias Jido.Agent
  alias Jido.Examples.AuthoringPlugin
  alias Jido.Examples.AuthoringPlugin.Labels

  test "DSL and Map authoring produce the same static contribution" do
    definition = AuthoringPlugin.Agent.definition()
    entry = %{id: "examples.labels", provider: Labels, vsn: 1, data: %{owner: "examples"}}

    assert definition.plugins == [entry]
    assert definition.metadata == %{}
    refute function_exported?(Labels, :__jido_plugin__, 0)
    assert Agent.runtime_plugins(definition) == []

    assert {:ok, from_map} = Agent.define(%{name: "map_labels", plugins: [entry]})
    assert from_map.plugins == definition.plugins
  end

  test "pure execution preserves the contribution while updating Agent state" do
    instance = AuthoringPlugin.Agent.instantiate!(id: "authoring-plugin")
    assert {:ok, signal} = AuthoringPlugin.Agent.add_signal(%{amount: 3})

    assert {:ok, result, []} = Agent.cmd(instance, signal)
    assert result.state == %{count: 3}
    assert instance.state == %{count: 0}
    assert result.plugins == instance.plugins
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
      assert {:error, %Agent.Error{path: [:plugins | _]}} =
               Agent.define(%{name: "invalid_labels", plugins: [invalid]})
    end
  end
end
