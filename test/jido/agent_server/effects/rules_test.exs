defmodule Jido.AgentServer.Effects.RulesTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive.{Emit, Reply}
  alias Jido.AgentServer.Effects

  defmodule Owned do
    use Jido.Agent.Directive
    defstruct [:value]
  end

  defmodule Unowned do
    use Jido.Agent.Directive
    defstruct []
  end

  defmodule Owner do
    use Jido.Plugin
    def directives(_opts), do: [Owned]
    def dispatch(_runtime, _directive, _context, _opts), do: :ok
  end

  test "effect deadlines and settlement have one small state model" do
    active = %{effect_deadline: 10, effects: [:one], effect_index: 0}

    assert Effects.next(active, 9) == {:effect, :one}
    assert Effects.next(active, 10) == :timed_out
    assert Effects.settle(active, :ok, 9) == :continue
    assert Effects.settle(active, :ok, 10) == :timed_out
    assert Effects.settle(%{}, {:reply, :value}, 0) == {:reply, :value}
    assert Effects.settle(%{}, :invalid, 0) == :failed
  end

  test "only core Signal effects and Plugin-owned typed effects validate" do
    signal = Jido.Signal.new!("effect.test", %{}, source: "/test")
    assert {:ok, [owner]} = Jido.Plugin.Normalizer.normalize_all([Owner])

    config = %{
      default_dispatch: {:pid, target: self()},
      max_directives_per_turn: 3,
      parent: nil,
      plugin_specs: [owner],
      requester: self()
    }

    assert :ok = Effects.validate_batch([%Emit{signal: signal}, %Owned{value: 1}], config)
    assert :ok = Effects.validate_batch([%Reply{signal: signal}], config)
    assert {:error, :unsupported_directive} = Effects.validate_batch([%Unowned{}], config)

    assert {:error, :too_many_directives} =
             Effects.validate_batch(List.duplicate(%Owned{}, 4), config)
  end

  test "Emit dispatches one prepared Signal" do
    source = Jido.Signal.new!("effect.source", %{}, source: "/test")
    outbound = Jido.Signal.new!("effect.outbound", %{value: 1}, source: "/test")
    trace = Jido.Trace.new()
    Jido.Trace.Context.put(trace)
    on_exit(&Jido.Trace.Context.clear/0)

    context = %{
      agent: Jido.Agent.define!(%{name: "effect_agent", signal_source: "/agent"}),
      default_dispatch: nil,
      effective_signal: source,
      jido: nil,
      partition: nil,
      plugin_refs: %{},
      plugin_specs: [],
      signal_id: source.id,
      source_signal: source,
      state_version: 0,
      turn_context: %{},
      turn_id: "turn"
    }

    assert :ok =
             Effects.run(
               %Emit{signal: outbound, dispatch: {:pid, target: self()}},
               nil,
               context
             )

    assert_receive {:signal, delivered}
    assert delivered.id == outbound.id
  end
end
