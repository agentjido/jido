defmodule JidoExampleTest.ScheduleDirectiveTest do
  @moduledoc """
  Example test demonstrating the Schedule directive for delayed work.

  This test shows:
  - How to schedule delayed signals/messages
  - Using Schedule for timeouts and retries
  - State machine patterns with scheduled transitions
  - Bounded retry logic without infinite loops

  Run with: mix test --include example
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 20_000

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.Signal

  # ===========================================================================
  # ACTIONS: Schedule-based patterns
  # ===========================================================================

  defmodule StartTimerAction do
    @moduledoc false
    use Jido.Action,
      name: "start_timer",
      schema: [
        delay_ms: [type: :integer, default: 100],
        timer_id: [type: :string, required: true]
      ]

    def run(%{delay_ms: delay_ms, timer_id: timer_id}, _context) do
      tick_signal = Signal.new!("timer.tick", %{timer_id: timer_id}, source: "/timer")

      schedule = %Directive.Schedule{
        delay_ms: delay_ms,
        message: tick_signal
      }

      {:ok, %{status: :waiting, timer_id: timer_id, started_at: DateTime.utc_now()}, schedule}
    end
  end

  defmodule HandleTickAction do
    @moduledoc false
    use Jido.Action,
      name: "handle_tick",
      schema: [
        timer_id: [type: :string, required: true]
      ]

    def run(%{timer_id: timer_id}, context) do
      tick_count = Map.get(context.state, :tick_count, 0) + 1
      {:ok, %{status: :ticked, tick_count: tick_count, last_tick_timer: timer_id}}
    end
  end

  defmodule StartRetryableAction do
    @moduledoc false
    use Jido.Action,
      name: "start_retryable",
      schema: [
        max_attempts: [type: :integer, default: 3],
        retry_delay_ms: [type: :integer, default: 50]
      ]

    def run(%{max_attempts: max, retry_delay_ms: delay}, _context) do
      retry_signal = Signal.new!("retry.attempt", %{}, source: "/retry")

      schedule = %Directive.Schedule{
        delay_ms: delay,
        message: retry_signal
      }

      {:ok, %{status: :retrying, attempts: 0, max_attempts: max, retry_delay_ms: delay}, schedule}
    end
  end

  defmodule HandleRetryAction do
    @moduledoc false
    use Jido.Action,
      name: "handle_retry",
      schema: []

    def run(_params, context) do
      attempts = Map.get(context.state, :attempts, 0) + 1
      max = Map.get(context.state, :max_attempts, 3)
      delay = Map.get(context.state, :retry_delay_ms, 50)

      if attempts >= max do
        {:ok, %{status: :completed, attempts: attempts, result: :success}}
      else
        retry_signal = Signal.new!("retry.attempt", %{}, source: "/retry")

        schedule = %Directive.Schedule{
          delay_ms: delay,
          message: retry_signal
        }

        {:ok, %{status: :retrying, attempts: attempts}, schedule}
      end
    end
  end

  defmodule StartTimeoutAction do
    @moduledoc false
    use Jido.Action,
      name: "start_timeout",
      schema: [
        timeout_ms: [type: :integer, default: 200],
        request_id: [type: :string, required: true]
      ]

    def run(%{timeout_ms: timeout_ms, request_id: request_id}, _context) do
      timeout_signal =
        Signal.new!("request.timeout", %{request_id: request_id}, source: "/timeout")

      schedule = %Directive.Schedule{
        delay_ms: timeout_ms,
        message: timeout_signal
      }

      {:ok, %{status: :waiting, request_id: request_id, pending_request: request_id}, schedule}
    end
  end

  defmodule HandleResponseAction do
    @moduledoc false
    use Jido.Action,
      name: "handle_response",
      schema: [
        request_id: [type: :string, required: true],
        result: [type: :any, required: true]
      ]

    def run(%{request_id: request_id, result: result}, context) do
      pending = Map.get(context.state, :pending_request)

      if pending == request_id do
        {:ok, %{status: :completed, result: result, pending_request: nil}}
      else
        {:ok, %{}}
      end
    end
  end

  defmodule HandleTimeoutAction do
    @moduledoc false
    use Jido.Action,
      name: "handle_timeout",
      schema: [
        request_id: [type: :string, required: true]
      ]

    def run(%{request_id: request_id}, context) do
      pending = Map.get(context.state, :pending_request)

      if pending == request_id do
        {:ok, %{status: :timed_out, pending_request: nil}}
      else
        {:ok, %{}}
      end
    end
  end

  # ===========================================================================
  # AGENT: Timer and retry patterns
  # ===========================================================================

  defmodule TimerAgent do
    @moduledoc false
    use Jido.Agent,
      name: "timer_agent",
      schema: [
        status: [type: :atom, default: :idle],
        timer_id: [type: :string, default: nil],
        tick_count: [type: :integer, default: 0],
        last_tick_timer: [type: :string, default: nil],
        attempts: [type: :integer, default: 0],
        max_attempts: [type: :integer, default: 3],
        retry_delay_ms: [type: :integer, default: 50],
        result: [type: :any, default: nil],
        request_id: [type: :string, default: nil],
        pending_request: [type: :string, default: nil],
        started_at: [type: :any, default: nil]
      ]

    def signal_routes(_ctx) do
      [
        {"start_timer", StartTimerAction},
        {"timer.tick", HandleTickAction},
        {"start_retryable", StartRetryableAction},
        {"retry.attempt", HandleRetryAction},
        {"start_timeout", StartTimeoutAction},
        {"response", HandleResponseAction},
        {"request.timeout", HandleTimeoutAction}
      ]
    end
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "basic scheduling" do
    test "Schedule directive triggers delayed signal", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, TimerAgent, id: unique_id("timer"))

      signal = Signal.new!("start_timer", %{timer_id: "T1", delay_ms: 50}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.status == :waiting
      assert agent.state.timer_id == "T1"

      eventually_state(
        pid,
        fn state -> state.agent.state.status == :ticked end,
        timeout: 3_000
      )

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.tick_count == 1
      assert state.agent.state.last_tick_timer == "T1"
    end
  end

  describe "retry pattern" do
    test "bounded retry eventually completes", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, TimerAgent, id: unique_id("retry"))

      signal =
        Signal.new!(
          "start_retryable",
          %{max_attempts: 3, retry_delay_ms: 30},
          source: "/test"
        )

      {:ok, agent} = AgentServer.call(pid, signal)
      assert agent.state.status == :retrying

      eventually_state(
        pid,
        fn state -> state.agent.state.status == :completed end,
        timeout: 5_000
      )

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.attempts == 3
      assert state.agent.state.result == :success
    end

    test "retry count matches max_attempts", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, TimerAgent, id: unique_id("retry"))

      signal =
        Signal.new!(
          "start_retryable",
          %{max_attempts: 5, retry_delay_ms: 20},
          source: "/test"
        )

      {:ok, _} = AgentServer.call(pid, signal)

      eventually_state(
        pid,
        fn state -> state.agent.state.status == :completed end,
        timeout: 5_000
      )

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.attempts == 5
    end
  end

  describe "timeout pattern" do
    test "response before timeout completes successfully", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, TimerAgent, id: unique_id("timeout"))

      start_signal =
        Signal.new!(
          "start_timeout",
          %{request_id: "REQ-1", timeout_ms: 500},
          source: "/test"
        )

      {:ok, _} = AgentServer.call(pid, start_signal)

      Process.sleep(50)

      response_signal =
        Signal.new!(
          "response",
          %{request_id: "REQ-1", result: "data"},
          source: "/test"
        )

      {:ok, agent} = AgentServer.call(pid, response_signal)

      assert agent.state.status == :completed
      assert agent.state.result == "data"
      assert agent.state.pending_request == nil
    end

    test "no response triggers timeout", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, TimerAgent, id: unique_id("timeout"))

      start_signal =
        Signal.new!(
          "start_timeout",
          %{request_id: "REQ-2", timeout_ms: 100},
          source: "/test"
        )

      {:ok, agent} = AgentServer.call(pid, start_signal)
      assert agent.state.status == :waiting

      eventually_state(
        pid,
        fn state -> state.agent.state.status == :timed_out end,
        timeout: 3_000
      )

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.pending_request == nil
    end

    test "late response after timeout is ignored", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, TimerAgent, id: unique_id("timeout"))

      start_signal =
        Signal.new!(
          "start_timeout",
          %{request_id: "REQ-3", timeout_ms: 50},
          source: "/test"
        )

      {:ok, _} = AgentServer.call(pid, start_signal)

      eventually_state(
        pid,
        fn state -> state.agent.state.status == :timed_out end,
        timeout: 2_000
      )

      late_response =
        Signal.new!(
          "response",
          %{request_id: "REQ-3", result: "late-data"},
          source: "/test"
        )

      {:ok, agent} = AgentServer.call(pid, late_response)

      assert agent.state.status == :timed_out
      assert agent.state.result == nil
    end
  end
end
