defmodule Jido.AgentServer.EmitDispatchTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Agent.Turn.Outcome
  alias Jido.Agent.Directive
  alias Jido.Signal
  alias Jido.Signal.Bus

  defmodule SendAction do
    use Jido.Action, name: "emit_dispatch_send"

    @impl Jido.Action
    def run(%{target: target, value: value}, context) do
      output = Signal.new!("dispatch.output", %{value: value}, source: "/directive/emit")
      state = %{context.agent_state | sends: context.agent_state.sends + 1}
      {:ok, state, [Directive.emit(output, {:pid, target: target})]}
    end
  end

  defmodule InvalidAction do
    use Jido.Action, name: "emit_dispatch_invalid"

    @impl Jido.Action
    def run(_params, context) do
      output = Signal.new!("dispatch.output", %{}, source: "/directive/emit")
      {:ok, %{context.agent_state | sends: 1}, [Directive.emit(output, {:pid, []})]}
    end
  end

  defmodule BusAction do
    use Jido.Action, name: "emit_dispatch_bus"

    @impl Jido.Action
    def run(_params, context) do
      output = Signal.new!("dispatch.bus.output", %{}, source: "/directive/emit")
      state = %{context.agent_state | sends: context.agent_state.sends + 1}
      {:ok, state, [Directive.emit(output, {:bus, target: :emit_dispatch_bus})]}
    end
  end

  defmodule Agent do
    use Jido.Agent, name: "emit_dispatch_agent"

    agent do
      schema Zoi.object(%{sends: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      route "dispatch.bus", BusAction
      route "dispatch.send", SendAction
      route "dispatch.invalid", InvalidAction
    end
  end

  test "reports the real post-commit dispatch result", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, Agent, id: unique_id("dispatch"))

    assert {:ok, agent} =
             Server.call(pid, signal("dispatch.send", %{target: self(), value: 7}))

    assert agent.state.sends == 1
    assert_receive {:signal, %Signal{type: "dispatch.output", data: %{value: 7}}}
    eventually(fn -> Server.status(pid).phase == :idle end)
  end

  test "rejects an invalid target before commit", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, Agent, id: unique_id("dispatch-invalid"))

    assert {:error, _reason} = Server.call(pid, signal("dispatch.invalid"))
    assert Server.agent(pid).state.sends == 0
  end

  test "rejects an Emit Directive with an invalid complete Signal" do
    invalid_signal = %{signal("dispatch.output") | source: "not a URI reference"}
    directive = Directive.emit(invalid_signal, {:pid, target: self()})

    assert {:error, errors} = Directive.validate(directive)
    assert Enum.any?(errors, &(&1.path == [:source]))
  end

  test "inherits the Agent Jido scope for a Bus target", %{jido: jido} do
    bus = start_supervised!({Bus, name: :emit_dispatch_bus, jido: jido})
    assert {:ok, _subscription} = Bus.subscribe(bus, "dispatch.bus.output")
    {:ok, pid} = Jido.start_agent(jido, Agent, id: unique_id("dispatch-bus"))

    assert {:ok, agent} = Server.call(pid, signal("dispatch.bus"))
    assert agent.state.sends == 1
    assert_receive {:signal, %Signal{type: "dispatch.bus.output"}}
  end

  test "turn failure keeps a state commit when delivery fails", %{jido: jido} do
    test = self()
    {dead_target, monitor} = spawn_monitor(fn -> :ok end)
    assert_receive {:DOWN, ^monitor, :process, ^dead_target, :normal}

    policy = fn reason, %Outcome{} = outcome ->
      send(test, {:dispatch_failed, reason, outcome})
      :continue
    end

    {:ok, pid} =
      Jido.start_agent(jido, Agent,
        id: unique_id("dispatch-failure"),
        error_policy: policy
      )

    assert {:ok, agent} =
             Server.call(pid, signal("dispatch.send", %{target: dead_target, value: 9}))

    assert agent.state.sends == 1

    assert_receive {:dispatch_failed, _reason,
                    %Outcome{stage: :directive, committed?: true, status: :failed}}

    eventually(fn -> Server.status(pid).phase == :idle end)
  end
end
