Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.Effects.RulesTest do
  use JidoTest.Case, async: true
  use Covenant.Case, component: "jido.agent_server.effects", async: true

  alias Jido.AgentServer.Effects
  alias Jido.Agent.Directive.Emit
  alias Jido.Signal.Dispatch
  alias Jido.Signal.Context, as: SignalContext
  alias Jido.Trace
  alias Jido.Trace.Context
  alias JidoTest.AgentServer.Fixtures, as: F

  defmodule Unowned do
    use Jido.Agent.Directive
    defstruct []
  end

  @tag obligation: "jido.agent_server.effects.I4"
  test "the exact effect deadline is expired" do
    active = %{effect_deadline: 10, effects: [:one], effect_index: 0}
    assert Effects.next(active, 10) == :timed_out
    assert Effects.next(active, 9) == {:effect, :one}
    assert Effects.settle(active, :ok, 10) == :timed_out
    assert Effects.settle(active, :ok, 9) == :continue
  end

  @tag obligation: "jido.agent_server.effects.I3"
  test "terminal effect results settle without losing their value" do
    assert Effects.settle(%{}, {:stop, :done}, 0) == {:stop, :done}
    assert Effects.settle(%{}, {:reported_error, :failed}, 0) == {:reported_error, :failed}
    assert Effects.settle(%{}, :invalid, 0) == :failed
  end

  @tag obligation: "jido.agent_server.effects.I1"
  test "a Plugin-owned state Directive does not need a runtime handler", c do
    config = config(c)
    assert :ok = Effects.validate_batch([%F.Effect{}], config)

    assert {:error, :unsupported_directive} =
             Effects.validate_batch([%Unowned{}], config)

    assert :ok =
             Effects.validate_batch(
               [%Unowned{}],
               %{config | directive_handler: fn _, _ -> :ok end}
             )
  end

  @tag obligation: "jido.agent_server.effects.I6"
  test "trace and dispatch owners propagate causation and bus scope" do
    source = F.signal()
    outbound = F.signal(%{}, "out")
    root = Trace.new()
    Context.put(root)
    on_exit(&Context.clear/0)

    assert {:ok, traced} = Context.propagate_to(outbound, source.id)
    assert SignalContext.get_trace(traced).trace_id == root.trace_id
    assert SignalContext.get_trace(traced).causation_id == source.id

    Context.clear()
    assert Context.propagate_to(outbound, source.id) == {:error, :no_trace_context}

    targets = [{:bus, target: :one}, {:pid, target: self()}]

    assert Dispatch.inherit_bus_scope(targets, Jido) == [
             {:bus, [jido: Jido, target: :one]},
             {:pid, target: self()}
           ]

    assert Dispatch.inherit_bus_scope({:bus, target: :one}, nil) ==
             {:bus, target: :one}

    assert Dispatch.inherit_bus_scope({:bus, target: :one}, "not-an-instance") ==
             {:bus, target: :one}
  end

  @tag obligation: "jido.agent_server.effects.I6"
  test "outbound dispatch returns the transport result", c do
    source = F.signal()
    outbound = F.signal(%{}, "out")
    agent = F.agent()
    Context.put(Trace.new())
    on_exit(&Context.clear/0)

    context = %{
      agent: agent,
      effective_signal: source,
      jido: c.jido,
      partition: nil,
      plugin_refs: %{},
      plugin_specs: [],
      signal_id: source.id,
      source_signal: source,
      state_version: 0,
      turn_context: %{},
      turn_id: "direct-dispatch"
    }

    assert :ok =
             Effects.run(%Emit{signal: outbound, dispatch: {:pid, target: self()}}, nil, context)

    assert_receive {:signal, delivered}, 1_000
    assert delivered.id == outbound.id
  end

  @tag obligation: "jido.agent_server.effects.I9"
  test "error reporting keeps a safe Signal when no trace can be propagated" do
    assert :continue =
             Effects.report_error(
               %{status: :failed},
               "agent",
               nil,
               {:pid, target: self()},
               nil
             )

    assert_receive {:signal, signal}, 1_000
    assert signal.type == "jido.agent_server.error"
    assert signal.data == %{status: :failed}
    assert SignalContext.get_trace(signal) == nil
  end

  defp config(c) do
    agent = F.agent()
    {:ok, specs} = Jido.Plugin.Normalizer.normalize_all(Jido.Agent.Plugin.declarations(agent))

    %{
      activation: self(),
      agent: agent,
      default_dispatch: nil,
      directive_handler: nil,
      jido: c.jido,
      max_directives_per_turn: 10,
      parent: nil,
      partition: nil,
      plugin_specs: specs,
      runner: Jido.Instance.Names.exec_runner(c.jido)
    }
  end
end
