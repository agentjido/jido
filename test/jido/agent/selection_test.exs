defmodule Jido.Agent.SelectionTest do
  use JidoTest.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.{Command, Runner, Turn}
  alias Jido.AgentServer, as: Server
  alias Jido.Signal
  alias Jido.Tracing.Trace

  defmodule Record do
    use Jido.Action, name: "selection_record"

    @impl true
    def run(input, context) do
      if observer = Map.get(context, :observer) do
        send(observer, {:executed, input, context.signal})
      end

      {:ok, %{input: input, calls: context.agent_state.calls + 1}}
    end
  end

  defmodule RecordFlow do
    use Jido.Flow, name: "selection_record_flow"

    flow do
      step "record", action: Record, params: input()
      output result("record")
    end
  end

  defmodule RoutedAgent do
    use Jido.Agent, name: "selection_routed"

    agent do
      schema Zoi.object(%{
               input: Zoi.map() |> Zoi.default(%{}),
               calls: Zoi.integer() |> Zoi.default(0)
             })
    end

    routes do
      route "selection.action", Record, defaults: %{value: 7, settings: %{first: 1, second: 2}}
      route "selection.flow", RecordFlow, defaults: %{value: 7, settings: %{first: 1, second: 2}}
    end
  end

  defmodule CustomAgent do
    use Jido.Agent, name: "selection_custom"

    agent do
      schema RoutedAgent.domain_schema()
    end

    routes do
      route "selection.action", Record, defaults: %{value: 7, settings: %{first: 1, second: 2}}
      route "selection.flow", RecordFlow, defaults: %{value: 7, settings: %{first: 1, second: 2}}
      route "selection.result", Record
    end

    @impl true
    def handle_signal(%Signal{type: "selection.raw", data: data}, _agent),
      do: Turn.new(Record, %{payload: data})

    def handle_signal(%Signal{type: "selection.state"}, agent) do
      target = if agent.state.calls == 0, do: Record, else: RecordFlow
      Turn.new(target, calls: agent.state.calls)
    end

    def handle_signal(%Signal{type: "selection.result", data: %{result: result}}, _agent),
      do: result

    def handle_signal(%Signal{type: "selection.fault", data: %{kind: :error}}, _agent),
      do: raise("selection failed")

    def handle_signal(%Signal{type: "selection.fault", data: %{kind: :throw}}, _agent),
      do: throw(:selection_failed)

    def handle_signal(%Signal{type: "selection.fault", data: %{kind: :exit}}, _agent),
      do: exit(:selection_failed)

    def handle_signal(signal, agent), do: Agent.handle_signal(signal, agent)
  end

  test "declared routes and explicit callback fallback prepare and execute the same Turn", %{
    jido: jido
  } do
    for module <- [RoutedAgent, CustomAgent],
        {type, target} <- [{"selection.action", Record}, {"selection.flow", RecordFlow}] do
      agent = module.new!()
      source = signal(type, %{value: 3, settings: %{second: 9}})
      input = %{value: 3, settings: %{second: 9}}

      assert {:ok, turn} = Agent.handle_signal(source, agent)
      assert turn == %Turn{executable: target, input: input, source_signal: source}
      assert {:ok, prepared} = Runner.prepare(agent, source, [])
      assert prepared.turn == turn

      assert {:ok, direct, []} = Agent.cmd(agent, source, context: %{observer: self()})
      assert_receive {:executed, ^input, ^source}
      assert direct.state == %{input: input, calls: 1}

      assert {:ok, server} = Jido.start_agent(jido, agent)
      assert {:ok, live} = Server.call(server, source, context: %{observer: self()})
      assert_receive {:executed, ^input, execution_signal}
      assert execution_signal.data == source.data
      assert live.state == direct.state
    end
  end

  test "custom selection can convert raw Signal data before input validation", %{jido: jido} do
    for data <- ["hello", [1, 2], nil] do
      agent = CustomAgent.new!()
      source = signal("selection.raw", data)
      assert {:ok, server} = Jido.start_agent(jido, agent)

      assert {:ok, direct, []} = Agent.cmd(agent, source)
      assert {:ok, live} = Server.call(server, source)
      assert direct.state == %{input: %{payload: data}, calls: 1}
      assert live.state == direct.state
    end
  end

  test "state selects the top-level executable without a continuation", %{jido: jido} do
    agent = CustomAgent.new!()
    source = signal("selection.state", nil)
    assert {:ok, server} = Jido.start_agent(jido, agent, exec_opts: [max_continuations: 0])

    assert {:ok, prepared} = Runner.prepare(agent, source, [])
    assert prepared.turn.executable == Record
    assert {:ok, first, []} = Agent.cmd(agent, source, max_continuations: 0)
    assert {:ok, live} = Server.call(server, source)
    assert first.state == %{input: %{calls: 0}, calls: 1}
    assert live.state == first.state

    assert {:ok, prepared} = Runner.prepare(first, source, [])
    assert prepared.turn.executable == RecordFlow
    assert {:ok, second, []} = Agent.cmd(first, source, max_continuations: 0)
    assert {:ok, live} = Server.call(server, source)
    assert second.state == %{input: %{calls: 1}, calls: 2}
    assert live.state == second.state
  end

  test "callback errors and invalid Turns fail before execution without route fallback", %{
    jido: jido
  } do
    agent = CustomAgent.new!()
    assert {:ok, server} = Jido.start_agent(jido, agent)

    results = [
      {:error, :rejected},
      {:error, Jido.Error.routing_error("Rejected", target: "selection.result")},
      :invalid,
      {:ok, :invalid},
      {:ok, %Turn{executable: String}},
      {:ok, %Turn{executable: Record, input: "invalid"}}
    ]

    for result <- results do
      source = signal("selection.result", %{result: result})
      assert {:error, error} = Agent.cmd(agent, source, context: %{observer: self()})
      assert {:error, live_error} = Server.call(server, source, context: %{observer: self()})

      case result do
        {:error, reason} ->
          assert error == reason
          assert live_error == reason

        _invalid ->
          assert Map.delete(error, :stacktrace) == Map.delete(live_error, :stacktrace)
      end

      assert Server.agent(server).state == agent.state
      assert Process.alive?(server)
      refute_received {:executed, _, _}
    end
  end

  test "callback errors, throws, and exits are contained in direct and live calls", %{jido: jido} do
    agent = CustomAgent.new!()
    assert {:ok, server} = Jido.start_agent(jido, agent)

    for kind <- [:error, :throw, :exit] do
      source = signal("selection.fault", %{kind: kind})

      assert {:error,
              %Jido.Error.ExecutionError{
                details: %{code: :agent_callback_failed, callback: :handle_signal, kind: ^kind}
              }} = Agent.cmd(agent, source)

      assert {:error,
              %Jido.Error.ExecutionError{
                details: %{code: :agent_callback_failed, callback: :handle_signal, kind: ^kind}
              }} = Server.call(server, source)

      assert Server.agent(server).state == agent.state
      assert Process.alive?(server)
    end
  end

  test "both selectors keep the original source separate from execution Signal metadata" do
    for module <- [RoutedAgent, CustomAgent] do
      source = signal("selection.action", %{})
      assert {:ok, command} = Command.new(module.new!(), source)
      assert {:ok, execution_signal} = Trace.put(source, Trace.new_root())
      refute execution_signal.extensions == source.extensions
      command = %{command | signal: execution_signal}

      assert {:ok, prepared} = Runner.prepare_for_server(command, source, [], [])
      assert prepared.turn.source_signal == source
      assert prepared.signal == execution_signal
      assert prepared.context.signal == execution_signal
    end
  end
end
