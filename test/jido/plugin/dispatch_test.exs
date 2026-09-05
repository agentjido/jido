defmodule Jido.Plugin.DispatchTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Agent.Turn.Outcome
  alias Jido.Plugin.Dispatch
  alias Jido.Signal
  alias Jido.Signal.Bus

  defmodule SendAction do
    use Jido.Action, name: "dispatch_plugin_send"

    @impl Jido.Action
    def run(%{target: target, value: value}, context) do
      output = Signal.new!("dispatch.output", %{value: value}, source: "/plugin/dispatch")
      state = %{context.agent_state | sends: context.agent_state.sends + 1}
      {:ok, state, [Dispatch.send(output, {:pid, target: target})]}
    end
  end

  defmodule InvalidAction do
    use Jido.Action, name: "dispatch_plugin_invalid"

    @impl Jido.Action
    def run(_params, context) do
      output = Signal.new!("dispatch.output", %{}, source: "/plugin/dispatch")
      {:ok, %{context.agent_state | sends: 1}, [Dispatch.send(output, {:pid, []})]}
    end
  end

  defmodule BusAction do
    use Jido.Action, name: "dispatch_plugin_bus"

    @impl Jido.Action
    def run(_params, context) do
      output = Signal.new!("dispatch.bus.output", %{}, source: "/plugin/dispatch")
      state = %{context.agent_state | sends: context.agent_state.sends + 1}
      {:ok, state, [Dispatch.send(output, {:bus, target: :dispatch_plugin_bus})]}
    end
  end

  defmodule Agent do
    use Jido.Agent,
      name: "dispatch_plugin_agent",
      schema: Zoi.object(%{sends: Zoi.integer() |> Zoi.default(0)}),
      routes: [
        {"dispatch.bus", BusAction},
        {"dispatch.send", SendAction},
        {"dispatch.invalid", InvalidAction}
      ],
      plugins: [Dispatch]
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

  test "inherits the Agent Jido scope for a Bus target", %{jido: jido} do
    bus = start_supervised!({Bus, name: :dispatch_plugin_bus, jido: jido})
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
