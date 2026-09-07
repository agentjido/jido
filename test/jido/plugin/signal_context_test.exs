defmodule Jido.Plugin.SignalContextTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin.SignalContext
  alias Jido.Signal

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
end
