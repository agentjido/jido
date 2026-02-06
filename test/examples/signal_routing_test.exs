defmodule JidoExampleTest.SignalRoutingTest do
  @moduledoc """
  Example test demonstrating signal routing via signal_routes/1.

  This test shows:
  - How to define signal_routes/1 to map signal types to actions
  - How signals are processed through AgentServer
  - How unhandled signals behave
  - Multiple signal types routed to different actions

  Run with: mix test --include example
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 15_000

  alias Jido.AgentServer
  alias Jido.Signal

  # ===========================================================================
  # ACTIONS: Handle different signal types
  # ===========================================================================

  defmodule IncrementAction do
    @moduledoc false
    use Jido.Action,
      name: "increment",
      schema: [
        amount: [type: :integer, default: 1]
      ]

    def run(%{amount: amount}, context) do
      current = Map.get(context.state, :counter, 0)
      {:ok, %{counter: current + amount}}
    end
  end

  defmodule SetNameAction do
    @moduledoc false
    use Jido.Action,
      name: "set_name",
      schema: [
        name: [type: :string, required: true]
      ]

    def run(%{name: name}, _context) do
      {:ok, %{name: name}}
    end
  end

  defmodule RecordEventAction do
    @moduledoc false
    use Jido.Action,
      name: "record_event",
      schema: [
        event_type: [type: :string, required: true],
        payload: [type: :map, default: %{}]
      ]

    def run(params, context) do
      events = Map.get(context.state, :events, [])

      event = %{
        type: params.event_type,
        payload: params.payload,
        recorded_at: DateTime.utc_now()
      }

      {:ok, %{events: [event | events]}}
    end
  end

  # ===========================================================================
  # AGENT: Routes signals to actions
  # ===========================================================================

  defmodule RoutedAgent do
    @moduledoc false
    use Jido.Agent,
      name: "routed_agent",
      schema: [
        counter: [type: :integer, default: 0],
        name: [type: :string, default: ""],
        events: [type: {:list, :map}, default: []]
      ]

    def signal_routes(_ctx) do
      [
        {"increment", IncrementAction},
        {"set_name", SetNameAction},
        {"record_event", RecordEventAction}
      ]
    end
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "signal routing basics" do
    test "signal type routes to mapped action", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, RoutedAgent, id: unique_id("routed"))

      signal = Signal.new!("increment", %{amount: 5}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.counter == 5
    end

    test "different signal types route to different actions", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, RoutedAgent, id: unique_id("routed"))

      increment_signal = Signal.new!("increment", %{amount: 10}, source: "/test")
      {:ok, _} = AgentServer.call(pid, increment_signal)

      name_signal = Signal.new!("set_name", %{name: "TestAgent"}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, name_signal)

      assert agent.state.counter == 10
      assert agent.state.name == "TestAgent"
    end

    test "signal data is passed as action params", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, RoutedAgent, id: unique_id("routed"))

      signal =
        Signal.new!(
          "record_event",
          %{event_type: "user.created", payload: %{user_id: 123}},
          source: "/test"
        )

      {:ok, agent} = AgentServer.call(pid, signal)

      assert length(agent.state.events) == 1
      [event] = agent.state.events
      assert event.type == "user.created"
      assert event.payload == %{user_id: 123}
    end
  end

  describe "multiple signals in sequence" do
    test "state accumulates across multiple signals", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, RoutedAgent, id: unique_id("routed"))

      signals = [
        Signal.new!("increment", %{amount: 1}, source: "/test"),
        Signal.new!("increment", %{amount: 2}, source: "/test"),
        Signal.new!("increment", %{amount: 3}, source: "/test")
      ]

      final_agent =
        Enum.reduce(signals, nil, fn signal, _acc ->
          {:ok, agent} = AgentServer.call(pid, signal)
          agent
        end)

      assert final_agent.state.counter == 6
    end

    test "different signal types interleave correctly", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, RoutedAgent, id: unique_id("routed"))

      {:ok, _} = AgentServer.call(pid, Signal.new!("increment", %{amount: 5}, source: "/test"))

      {:ok, _} =
        AgentServer.call(pid, Signal.new!("set_name", %{name: "Counter"}, source: "/test"))

      {:ok, _} =
        AgentServer.call(
          pid,
          Signal.new!("record_event", %{event_type: "checkpoint"}, source: "/test")
        )

      {:ok, _} = AgentServer.call(pid, Signal.new!("increment", %{amount: 3}, source: "/test"))

      {:ok, state} = AgentServer.state(pid)

      assert state.agent.state.counter == 8
      assert state.agent.state.name == "Counter"
      assert length(state.agent.state.events) == 1
    end
  end

  describe "async signal processing (cast)" do
    test "cast sends signal without waiting for response", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, RoutedAgent, id: unique_id("routed"))

      signal = Signal.new!("increment", %{amount: 7}, source: "/test")
      :ok = AgentServer.cast(pid, signal)

      eventually_state(
        pid,
        fn state -> state.agent.state.counter == 7 end,
        timeout: 2_000
      )
    end

    test "multiple casts process in order", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, RoutedAgent, id: unique_id("routed"))

      for i <- 1..5 do
        signal = Signal.new!("increment", %{amount: i}, source: "/test")
        :ok = AgentServer.cast(pid, signal)
      end

      eventually_state(
        pid,
        fn state -> state.agent.state.counter == 15 end,
        timeout: 2_000
      )
    end
  end
end
