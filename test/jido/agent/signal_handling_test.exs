defmodule JidoTest.Agent.SignalHandlingTest do
  @moduledoc """
  Tests signal routing through AgentServer.

  Signal handling architecture:
  1. Signals arrive at AgentServer
  2. AgentServer routes signals to actions via strategy.signal_routes or default mapping
  3. Actions are executed via Agent.cmd/2
  4. on_before_cmd/2 can intercept actions for pre-processing
  """
  use JidoTest.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.Signal
  alias JidoTest.TestActions

  defmodule EmitTestAction do
    @moduledoc false
    use Jido.Action, name: "emit_test", schema: []

    def run(_params, _context) do
      signal = Signal.new!("test.emitted", %{from: "agent"}, source: "/test")
      {:ok, %{}, [%Directive.Emit{signal: signal}]}
    end
  end

  # Agent with actions for signal routing
  defmodule ActionBasedAgent do
    @moduledoc false
    use Jido.Agent,
      name: "action_based_agent",
      schema: [
        counter: [type: :integer, default: 0],
        messages: [type: {:list, :any}, default: []]
      ]

    def signal_routes(_ctx) do
      [
        {"increment", TestActions.IncrementAction},
        {"decrement", TestActions.DecrementAction},
        {"record", TestActions.RecordAction},
        {"emit_test", EmitTestAction}
      ]
    end
  end

  # Agent with on_before_cmd hook for pre-processing
  defmodule PreProcessingAgent do
    @moduledoc false
    use Jido.Agent,
      name: "pre_processing_agent",
      schema: [
        counter: [type: :integer, default: 0],
        last_action_type: [type: :string, default: nil]
      ]

    def signal_routes(_ctx) do
      [
        {"increment", TestActions.IncrementAction},
        {"decrement", TestActions.DecrementAction}
      ]
    end

    # Intercept actions to capture the action type before processing
    # Handles action module tuples from signal routing
    def on_before_cmd(agent, {action_mod, _params} = action) when is_atom(action_mod) do
      action_name = action_mod.__action_metadata__().name
      agent = %{agent | state: Map.put(agent.state, :last_action_type, action_name)}
      {:ok, agent, action}
    end

    def on_before_cmd(agent, action), do: {:ok, agent, action}
  end

  describe "signal routing via AgentServer" do
    test "signals are routed to actions by type", %{jido: jido} do
      {:ok, pid} =
        Jido.AgentServer.start_link(agent: ActionBasedAgent, id: "signal-route-test", jido: jido)

      # Signal type becomes the action: {"increment", signal.data}
      signal = Signal.new!("increment", %{amount: 5}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      # The IncrementAction should have been called
      assert agent.state.counter == 5

      GenServer.stop(pid)
    end

    test "multiple signals processed in sequence", %{jido: jido} do
      {:ok, pid} =
        Jido.AgentServer.start_link(agent: ActionBasedAgent, id: "multi-signal-test", jido: jido)

      signals = [
        Signal.new!("increment", %{amount: 1}, source: "/test"),
        Signal.new!("increment", %{amount: 2}, source: "/test"),
        Signal.new!("increment", %{amount: 3}, source: "/test")
      ]

      final_agent =
        Enum.reduce(signals, nil, fn signal, _acc ->
          {:ok, agent} = Jido.AgentServer.call(pid, signal)
          agent
        end)

      assert final_agent.state.counter == 6

      GenServer.stop(pid)
    end

    test "signal data is passed to action", %{jido: jido} do
      {:ok, pid} =
        Jido.AgentServer.start_link(agent: ActionBasedAgent, id: "signal-data-test", jido: jido)

      signal = Signal.new!("record", %{message: "hello"}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      # Fixtures.RecordAction stores the :message value when present
      assert agent.state.messages == ["hello"]

      GenServer.stop(pid)
    end

    test "action can return directives", %{jido: jido} do
      {:ok, pid} =
        Jido.AgentServer.start_link(agent: ActionBasedAgent, id: "directive-test", jido: jido)

      signal = Signal.new!("emit_test", %{}, source: "/test")
      {:ok, _agent} = Jido.AgentServer.call(pid, signal)

      # Directive was processed (we can't easily verify Emit was executed,
      # but we verified the action ran without error)
      GenServer.stop(pid)
    end

    test "unknown signal type produces routing error", %{jido: jido} do
      {:ok, pid} =
        Jido.AgentServer.start_link(
          agent: ActionBasedAgent,
          id: "unknown-signal-test",
          jido: jido
        )

      signal = Signal.new!("unknown_action", %{}, source: "/test")
      assert {:error, %Jido.Error.RoutingError{} = error} = Jido.AgentServer.call(pid, signal)
      assert error.details.reason == :no_matching_route

      # The agent should still be functional despite the error
      signal2 = Signal.new!("increment", %{amount: 1}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal2)
      assert agent.state.counter == 1

      GenServer.stop(pid)
    end
  end

  describe "on_before_cmd/2 hook" do
    test "on_before_cmd can modify state before action runs", %{jido: jido} do
      {:ok, pid} =
        Jido.AgentServer.start_link(agent: PreProcessingAgent, id: "before-cmd-test", jido: jido)

      signal = Signal.new!("increment", %{amount: 1}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      # on_before_cmd captured the action type
      assert agent.state.last_action_type == "increment"
      # Action still ran
      assert agent.state.counter == 1

      GenServer.stop(pid)
    end

    test "on_before_cmd can modify action", %{jido: jido} do
      defmodule ActionModifyingAgent do
        @moduledoc false
        use Jido.Agent,
          name: "action_modifying_agent",
          schema: [counter: [type: :integer, default: 0]]

        alias JidoTest.TestActions

        def signal_routes(_ctx) do
          [
            {"increment", TestActions.IncrementAction}
          ]
        end

        # Transform action to always increment by 10
        # Matches on the action module, not string type
        def on_before_cmd(agent, {TestActions.IncrementAction, _params}) do
          {:ok, agent, {TestActions.IncrementAction, %{amount: 10}}}
        end

        def on_before_cmd(agent, action), do: {:ok, agent, action}
      end

      {:ok, pid} =
        Jido.AgentServer.start_link(
          agent: ActionModifyingAgent,
          id: "modify-action-test",
          jido: jido
        )

      signal = Signal.new!("increment", %{amount: 1}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      # Action was modified to increment by 10
      assert agent.state.counter == 10

      GenServer.stop(pid)
    end
  end

  describe "direct cmd/2 usage" do
    test "cmd/2 works directly with action module tuples" do
      agent = ActionBasedAgent.new()

      {updated, _directives} =
        ActionBasedAgent.cmd(agent, {TestActions.IncrementAction, %{amount: 5}})

      assert updated.state.counter == 5
    end

    test "cmd/2 calls on_before_cmd with action module" do
      agent = PreProcessingAgent.new()

      {updated, _directives} =
        PreProcessingAgent.cmd(agent, {TestActions.IncrementAction, %{amount: 1}})

      # on_before_cmd now captures action module name
      assert updated.state.last_action_type == "increment"
      assert updated.state.counter == 1
    end
  end
end
