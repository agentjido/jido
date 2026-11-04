defmodule JidoTest.AgentServer.EffectsApiTest do
  use Covenant.Case, component: "jido.agent_server.effects", async: true

  import Jido.Test.PublicAPI

  alias Jido.Agent.Directive, as: AgentDirective
  alias Jido.Agent.Directive.{AgentSend, Emit, ParentSend, ServerStop}
  alias Jido.AgentServer.Directive

  alias Jido.AgentServer.Directive.{AgentStart, AgentStop, ErrorReport, ProcessStart}

  alias Jido.AgentServer.Effects
  alias Jido.Signal
  alias Jido.Test.Agent.EvolutionFixtures, as: E

  @records [AgentSend, AgentStart, AgentStop, ErrorReport, ParentSend, ProcessStart, ServerStop]

  @tag obligation: "jido.agent_server.effects.I12"
  test "the documented runtime Directive API and public types are exact" do
    assert documented_api(Directive) == [
             {:function, :agent_start, 3},
             {:function, :agent_stop, 2},
             {:function, :error_report, 2},
             {:function, :process_start, 1},
             {:function, :signal_send, 3}
           ]

    assert documented_types(Directive) == [
             {:type, :agent_start_option, 0},
             {:type, :restart_policy, 0},
             {:type, :signal_send_option, 0},
             {:type, :t, 0}
           ]

    assert public_module?(Directive)

    for module <- @records do
      assert public_module?(module)
      assert documented_api(module) == []
      assert documented_types(module) == [{:type, :t, 0}]
    end

    refute public_module?(Effects)
  end

  @tag obligation: "jido.agent_server.effects.I12"
  test "runtime Directive constructors keep closed unique options and stable results" do
    signal = Signal.new!("effect.test", %{}, source: "/test")
    formatter = &{:effect, &1}

    assert %Emit{signal: ^signal, dispatch: {:pid, dispatch}} =
             Directive.signal_send(signal, self(),
               delivery_mode: :sync,
               timeout: 100,
               message_format: formatter
             )

    assert dispatch[:target] == self()
    assert dispatch[:delivery_mode] == :sync
    assert dispatch[:timeout] == 100
    assert dispatch[:message_format] == formatter
    assert %AgentSend{name: :child, signal: ^signal} = AgentDirective.agent_send(:child, signal)
    assert %ParentSend{signal: ^signal} = AgentDirective.parent_send(signal)

    assert %ErrorReport{error: :failed, context: :turn} =
             Directive.error_report(:failed, :turn)

    assert %ProcessStart{child_spec: Task} = Directive.process_start(Task)

    assert %AgentStart{
             agent: __MODULE__,
             name: :child,
             opts: %{id: "child"},
             meta: %{role: :worker},
             restart: :temporary
           } =
             Directive.agent_start(__MODULE__, :child,
               opts: [id: "child"],
               meta: [role: :worker],
               restart: :temporary
             )

    assert %AgentStop{name: :child, reason: :shutdown} =
             Directive.agent_stop(:child, :shutdown)

    assert %ServerStop{reason: :shutdown} = AgentDirective.server_stop(:shutdown)

    for invalid <- [
          [unknown: true],
          [restart: :permanent, restart: :temporary],
          [opts: [id: "first", id: "second"]],
          [meta: %URI{}]
        ] do
      assert_raise ArgumentError, fn -> Directive.agent_start(__MODULE__, :child, invalid) end
    end

    assert_raise ArgumentError, fn ->
      Directive.signal_send(signal, self(), timeout: 10, timeout: 20)
    end
  end

  @tag obligation: ["jido.agent_server.effects.I10", "jido.agent_server.effects.I12"]
  test "hidden validation hooks protect runtime Directive inputs before commit" do
    for policy <- [:permanent, :temporary, :transient] do
      directive = Directive.agent_start(E.Worker, :child, restart: policy)
      assert {:ok, ^directive} = AgentDirective.validate(directive)
      assert :ok = Directive.AgentStart.validate_restart(policy)
    end

    stop = AgentDirective.server_stop()
    assert {:ok, ^stop} = AgentDirective.validate(stop)

    assert {:error, message} = Directive.AgentStart.validate_restart(:invalid)
    assert message != ""

    for key <- [
          :agent,
          :jido,
          :partition,
          :runner,
          :node,
          :lifecycle_mod,
          :pool,
          :pool_key,
          :idle_timeout,
          :persistence,
          :restore,
          :state_version
        ] do
      assert {:error, message} = Directive.AgentStart.validate_options(%{key => :invalid})
      assert message != ""
    end

    assert {:error, message} = Directive.AgentStart.validate_options([])
    assert message != ""

    invalid = %{E.Worker.instantiate!(id: "invalid-effect-target") | state: %{count: :invalid}}
    assert {:error, _} = Directive.AgentStart.validate_target(invalid)
    assert {:error, {:invalid_agent, 42}} = Directive.AgentStart.validate_target(42)
  end
end
