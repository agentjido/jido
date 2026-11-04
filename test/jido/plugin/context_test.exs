defmodule Jido.Plugin.ContextTest do
  use Covenant.Case, component: "jido.plugin", async: true

  alias Jido.Plugin.{Context, Init, Input}
  alias Jido.Signal

  @tag obligation: "jido.plugin.I9"
  test "schema accepts the complete narrow outbound context" do
    source = Signal.new!("plugin.source", %{}, source: "/test")

    attrs = %{
      phase: :signal,
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

    assert {:ok, %Context{phase: :signal} = context} =
             Jido.Joi.parse(Context.schema(:signal), attrs)

    assert Map.from_struct(context) == attrs

    assert {:error, _reason} =
             Jido.Joi.parse(Context.schema(:signal), Map.put(attrs, :extra, true))
  end

  @tag obligation: "jido.plugin.I9"
  test "schema supplies transient defaults and rejects invalid identity fields" do
    source = Signal.new!("plugin.source", %{}, source: "/test")

    required = %{
      phase: :signal,
      turn_id: "turn-1",
      agent_id: "agent-1",
      source_signal: source,
      effective_signal: source,
      target: self(),
      state_version: 0,
      plugin_state: nil
    }

    assert {:ok, %Context{phase: :signal, turn_context: %{}}} =
             Jido.Joi.parse(Context.schema(:signal), required)

    for changes <- [
          %{phase: :directive},
          %{turn_id: 1},
          %{agent_id: nil},
          %{source_signal: :invalid},
          %{effective_signal: :invalid},
          %{state_version: -1}
        ] do
      assert {:error, _reason} =
               Jido.Joi.parse(Context.schema(:signal), Map.merge(required, changes))
    end

    for key <- [:phase, :target] do
      assert {:error, _reason} =
               Jido.Joi.parse(Context.schema(:signal), Map.delete(required, key))
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

    assert {:ok, %Init{} = init} = Jido.Joi.parse(Init.schema(), attrs)
    assert Map.from_struct(init) == attrs

    assert {:ok, %Init{state_version: 0, options: []}} =
             Jido.Joi.parse(Init.schema(), Map.take(attrs, [:agent_server, :agent_id, :module]))

    for key <- [:agent_server, :agent_id, :module] do
      assert {:error, _reason} = Jido.Joi.parse(Init.schema(), Map.delete(attrs, key))
    end

    assert {:error, _reason} = Jido.Joi.parse(Init.schema(), %{attrs | state_version: -1})
    assert {:error, _reason} = Jido.Joi.parse(Init.schema(), Map.put(attrs, :extra, true))
    assert {:error, _reason} = Jido.Joi.parse(Init.schema(), %{attrs | options: [:invalid]})
  end

  @tag obligation: "jido.plugin.I9"
  test "directive schema preserves its complete narrow value" do
    source = Signal.new!("plugin.source", %{}, source: "/test")

    attrs = %{
      phase: :directive,
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

    assert {:ok, %Context{phase: :directive} = context} =
             Jido.Joi.parse(Context.schema(:directive), attrs)

    assert Map.from_struct(context) == Map.put(attrs, :target, nil)

    assert {:ok, %Context{phase: :directive, turn_context: %{}}} =
             Jido.Joi.parse(
               Context.schema(:directive),
               Map.drop(attrs, [:turn_context, :jido, :partition])
             )

    for key <- [
          :phase,
          :turn_id,
          :agent_id,
          :source_signal,
          :effective_signal,
          :state_version,
          :plugin_state
        ] do
      assert {:error, _reason} =
               Jido.Joi.parse(Context.schema(:directive), Map.delete(attrs, key))
    end

    assert {:error, _reason} =
             Jido.Joi.parse(Context.schema(:directive), %{attrs | state_version: -1})

    assert {:error, _reason} =
             Jido.Joi.parse(Context.schema(:directive), Map.put(attrs, :extra, true))

    assert {:error, _reason} =
             Jido.Joi.parse(Context.schema(:directive), Map.put(attrs, :target, self()))
  end
end
