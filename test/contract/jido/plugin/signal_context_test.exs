defmodule Jido.Plugin.SignalContextTest do
  use Covenant.Case, component: "jido.plugin", async: true

  alias Jido.Plugin.{DirectiveContext, Init, Input, SignalContext}
  alias Jido.Signal

  @tag obligation: "jido.plugin.I9"
  test "schema accepts the complete narrow outbound context" do
    source = Signal.new!("plugin.source", %{}, source: "/test")

    attrs = %{
      turn_id: "turn-1",
      agent_id: "agent-1",
      source_signal: source,
      effective_signal: source,
      turn_context: %{caller: self()},
      target: {:bus, :events},
      state_version: 2,
      plugin_state: %{count: 1},
      jido: :test_jido,
      partition: "west"
    }

    assert {:ok, %SignalContext{} = context} = Zoi.parse(SignalContext.schema(), attrs)
    assert Map.from_struct(context) == attrs
  end

  @tag obligation: "jido.plugin.I9"
  test "schema supplies transient defaults and rejects invalid identity fields" do
    source = Signal.new!("plugin.source", %{}, source: "/test")

    required = %{
      turn_id: "turn-1",
      agent_id: "agent-1",
      source_signal: source,
      effective_signal: source,
      target: self(),
      state_version: 0,
      plugin_state: nil
    }

    assert {:ok, %SignalContext{turn_context: %{}}} =
             Zoi.parse(SignalContext.schema(), required)

    for changes <- [
          %{turn_id: 1},
          %{agent_id: nil},
          %{source_signal: :invalid},
          %{effective_signal: :invalid},
          %{state_version: -1}
        ] do
      assert {:error, _reason} = Zoi.parse(SignalContext.schema(), Map.merge(required, changes))
    end
  end

  @tag obligation: "jido.plugin.I9"
  test "input keeps prepared and runtime values separate" do
    input = %Input{} |> Input.put_prepared(%{pure: 1}) |> Input.put_runtime(self())

    assert input == %Input{prepared: %{pure: 1}, runtime: self()}
  end

  @tag obligation: "jido.plugin.I9"
  test "initialization schema preserves its complete narrow value" do
    attrs = %{
      agent_server: self(),
      agent_id: "agent-1",
      module: __MODULE__,
      plugin_state: %{count: 1},
      state_version: 0,
      jido: :test_jido,
      partition: "west",
      options: [label: "test"]
    }

    assert {:ok, %Init{} = init} = Zoi.parse(Init.schema(), attrs)
    assert Map.from_struct(init) == attrs

    assert {:ok, %Init{state_version: 0, options: []}} =
             Zoi.parse(Init.schema(), Map.take(attrs, [:agent_server, :agent_id, :module]))

    for key <- [:agent_server, :agent_id, :module] do
      assert {:error, _reason} = Zoi.parse(Init.schema(), Map.delete(attrs, key))
    end

    assert {:error, _reason} = Zoi.parse(Init.schema(), %{attrs | state_version: -1})
  end

  @tag obligation: "jido.plugin.I9"
  test "directive schema preserves its complete narrow value" do
    source = Signal.new!("plugin.source", %{}, source: "/test")

    attrs = %{
      turn_id: "turn-1",
      agent_id: "agent-1",
      source_signal: source,
      effective_signal: source,
      state_version: 0,
      plugin_state: %{count: 1},
      turn_context: %{caller: self()},
      jido: :test_jido,
      partition: "west"
    }

    assert {:ok, %DirectiveContext{} = context} =
             Zoi.parse(DirectiveContext.schema(), attrs)

    assert Map.from_struct(context) == attrs

    assert {:ok, %DirectiveContext{turn_context: %{}}} =
             Zoi.parse(
               DirectiveContext.schema(),
               Map.drop(attrs, [:turn_context, :jido, :partition])
             )

    for key <- [
          :turn_id,
          :agent_id,
          :source_signal,
          :effective_signal,
          :state_version,
          :plugin_state
        ] do
      assert {:error, _reason} = Zoi.parse(DirectiveContext.schema(), Map.delete(attrs, key))
    end

    assert {:error, _reason} = Zoi.parse(DirectiveContext.schema(), %{attrs | state_version: -1})
  end
end
