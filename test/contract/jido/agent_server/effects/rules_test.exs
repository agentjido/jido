Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.Effects.RulesTest do
  use JidoTest.Case, async: true
  use Covenant.Case, component: "jido.agent_server.effects", async: true

  alias Jido.AgentServer.Effects
  alias Jido.Dispatch.Preparation
  alias Jido.Tracing.{Context, Trace}
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
  test "dispatch preparation propagates causation and keeps safe fallbacks" do
    source = F.signal()
    outbound = F.signal(%{}, "out")
    root = Trace.new_root()
    Context.put(root)
    on_exit(&Context.clear/0)

    traced = Preparation.propagate(outbound, source)
    assert Trace.get(traced).trace_id == root.trace_id
    assert Trace.get(traced).causation_id == source.id

    Context.clear()
    assert Preparation.propagate(outbound, source) == outbound

    targets = [{:bus, target: :one}, {:pid, target: self()}]

    assert Preparation.inherit_bus_scope(targets, Jido) == [
             {:bus, [jido: Jido, target: :one]},
             {:pid, target: self()}
           ]

    assert Preparation.inherit_bus_scope({:bus, target: :one}, nil) ==
             {:bus, target: :one}

    assert Preparation.inherit_bus_scope({:bus, target: :one}, "not-an-instance") ==
             {:bus, target: :one}
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
    assert Trace.get(signal) == nil
  end

  defp config(c) do
    agent = F.agent()
    {:ok, specs} = Jido.Plugin.Normalizer.normalize_all(Jido.Agent.runtime_plugins(agent))

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
      runner: Jido.exec_runner_name(c.jido)
    }
  end
end
