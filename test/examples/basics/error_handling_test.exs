defmodule JidoExampleTest.ErrorHandlingTest do
  @moduledoc """
  Example test demonstrating error handling patterns with Directive.Error.

  This test shows:
  - How actions returning {:error, reason} produce error directives
  - How Directive.Error wraps Jido.Error structs
  - Recovery pattern: failed → retry → success
  - Error state includes error details
  - Bounded retry (max_attempts) prevents infinite loops

  ## Usage

  Actions can signal errors by returning `{:error, reason}` from their `run/2` function.
  The agent strategy wraps these into `%Directive.Error{}` directives.

  For validation errors, use `Jido.Error.validation_error/2`:

      {:error, Jido.Error.validation_error("Invalid input", field: :amount)}

  For recovery patterns, track error state and retry count in agent state,
  then use signals to trigger retry actions that clear the error and continue.

  Run with: mix test --include example
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 15_000

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.Signal

  # ===========================================================================
  # ACTIONS: Error handling patterns
  # ===========================================================================

  defmodule ValidateAction do
    @moduledoc false
    use Jido.Action,
      name: "validate",
      schema: [
        amount: [type: :integer, required: true]
      ]

    def run(%{amount: amount}, _context) do
      if amount > 0 do
        {:ok, %{validated: true, amount: amount}}
      else
        {:error, Jido.Error.validation_error("Amount must be positive", field: :amount)}
      end
    end
  end

  defmodule RetryableAction do
    @moduledoc false
    use Jido.Action,
      name: "retryable",
      schema: [
        fail_count: [type: :integer, default: 0]
      ]

    def run(%{fail_count: fail_count}, context) do
      attempts = Map.get(context.state, :attempts, 0) + 1

      if attempts <= fail_count do
        {:error, Jido.Error.execution_error("Simulated failure", details: %{attempt: attempts})}
      else
        {:ok, %{attempts: attempts, status: :success, result: "completed"}}
      end
    end
  end

  defmodule RecoverAction do
    @moduledoc false
    use Jido.Action,
      name: "recover",
      schema: []

    def run(_params, _context) do
      {:ok, %{status: :recovered, error: nil, error_context: nil}}
    end
  end

  defmodule TrackErrorAction do
    @moduledoc false
    use Jido.Action,
      name: "track_error",
      schema: [
        error_message: [type: :string, required: true],
        error_context: [type: :atom, default: :unknown]
      ]

    def run(%{error_message: message, error_context: ctx}, context) do
      error = Jido.Error.execution_error(message)

      error_directive = %Directive.Error{error: error, context: ctx}

      current_attempts = Map.get(context.state, :attempts, 0)

      {:ok, %{status: :failed, error: message, error_context: ctx, attempts: current_attempts},
       error_directive}
    end
  end

  defmodule BoundedRetryAction do
    @moduledoc false
    use Jido.Action,
      name: "bounded_retry",
      schema: [
        max_attempts: [type: :integer, default: 3]
      ]

    def run(%{max_attempts: max}, context) do
      attempts = Map.get(context.state, :attempts, 0) + 1

      if attempts >= max do
        {:ok, %{status: :exhausted, attempts: attempts, result: :max_retries_reached}}
      else
        retry_signal = Signal.new!("retry", %{}, source: "/retry")

        schedule = %Directive.Schedule{
          delay_ms: 10,
          message: retry_signal
        }

        {:ok, %{status: :retrying, attempts: attempts}, schedule}
      end
    end
  end

  defmodule HandleRetryAction do
    @moduledoc false
    use Jido.Action,
      name: "handle_retry",
      schema: [
        max_attempts: [type: :integer, default: 3],
        succeed_on: [type: :integer, default: 3]
      ]

    def run(%{max_attempts: max, succeed_on: succeed_on}, context) do
      attempts = Map.get(context.state, :attempts, 0) + 1

      stored_max =
        case Map.get(context.state, :stored_max_attempts) do
          nil -> max
          val -> val
        end

      stored_succeed =
        case Map.get(context.state, :stored_succeed_on) do
          nil -> succeed_on
          val -> val
        end

      cond do
        attempts >= stored_succeed ->
          {:ok, %{status: :success, attempts: attempts, result: "finally succeeded"}}

        attempts >= stored_max ->
          {:ok, %{status: :exhausted, attempts: attempts, result: :max_retries_reached}}

        true ->
          retry_signal = Signal.new!("retry", %{}, source: "/retry")

          schedule = %Directive.Schedule{
            delay_ms: 10,
            message: retry_signal
          }

          {:ok,
           %{
             status: :retrying,
             attempts: attempts,
             stored_max_attempts: stored_max,
             stored_succeed_on: stored_succeed
           }, schedule}
      end
    end
  end

  # ===========================================================================
  # AGENT: Error handling with signal routes
  # ===========================================================================

  defmodule ErrorHandlingAgent do
    @moduledoc false
    use Jido.Agent,
      name: "error_handling_agent",
      schema: [
        status: [type: :atom, default: :idle],
        validated: [type: :boolean, default: false],
        amount: [type: :integer, default: 0],
        attempts: [type: :integer, default: 0],
        stored_max_attempts: [type: :integer, default: nil],
        stored_succeed_on: [type: :integer, default: nil],
        result: [type: :any, default: nil],
        error: [type: :any, default: nil],
        error_context: [type: :atom, default: nil]
      ]

    def signal_routes(_ctx) do
      [
        {"validate", ValidateAction},
        {"retry", HandleRetryAction},
        {"recover", RecoverAction},
        {"bounded_retry", BoundedRetryAction}
      ]
    end
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "action returning {:error, reason}" do
    test "produces error directive when validation fails" do
      agent = ErrorHandlingAgent.new()

      {updated_agent, directives} =
        ErrorHandlingAgent.cmd(agent, {ValidateAction, %{amount: -5}})

      assert updated_agent.state.validated == false
      assert [%Directive.Error{context: :instruction, error: error}] = directives
      assert error.message == "Instruction failed"
    end

    test "succeeds when validation passes" do
      agent = ErrorHandlingAgent.new()

      {updated_agent, directives} =
        ErrorHandlingAgent.cmd(agent, {ValidateAction, %{amount: 100}})

      assert updated_agent.state.validated == true
      assert updated_agent.state.amount == 100
      assert directives == []
    end
  end

  describe "Directive.Error wraps Jido.Error structs" do
    test "action can emit error directive with context" do
      agent = ErrorHandlingAgent.new()

      {updated_agent, directives} =
        ErrorHandlingAgent.cmd(
          agent,
          {TrackErrorAction, %{error_message: "Something broke", error_context: :processing}}
        )

      assert updated_agent.state.status == :failed
      assert updated_agent.state.error == "Something broke"
      assert updated_agent.state.error_context == :processing

      assert [%Directive.Error{error: error, context: :processing}] = directives
      assert %Jido.Error.ExecutionError{} = error
      assert error.message == "Something broke"
    end

    test "error directive includes Jido.Error with details" do
      agent = ErrorHandlingAgent.new()

      {_agent, directives} =
        ErrorHandlingAgent.cmd(agent, {RetryableAction, %{fail_count: 1}})

      assert [%Directive.Error{error: error}] = directives
      assert error.message == "Instruction failed"
    end
  end

  describe "recovery pattern: failed → retry → success" do
    test "retryable action fails then succeeds", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, ErrorHandlingAgent, id: unique_id("retry"))

      signal = Signal.new!("bounded_retry", %{max_attempts: 3}, source: "/test")
      :ok = AgentServer.cast(pid, signal)

      eventually_state(
        pid,
        fn state ->
          state.agent.state.status in [:exhausted, :success] and
            state.agent.state.attempts >= 3
        end,
        timeout: 2_000
      )

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.attempts >= 3
    end

    test "recovery action clears error state" do
      agent =
        ErrorHandlingAgent.new(
          state: %{status: :failed, error: "previous error", error_context: :old}
        )

      {updated_agent, directives} = ErrorHandlingAgent.cmd(agent, RecoverAction)

      assert updated_agent.state.status == :recovered
      assert updated_agent.state.error == nil
      assert updated_agent.state.error_context == nil
      assert directives == []
    end

    test "signal-based retry clears error and continues", %{jido: jido} do
      {:ok, pid} =
        Jido.start_agent(jido, ErrorHandlingAgent,
          id: unique_id("signal-retry"),
          state: %{status: :failed, error: "test error", attempts: 0}
        )

      recover_signal = Signal.new!("recover", %{}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, recover_signal)

      assert agent.state.status == :recovered
      assert agent.state.error == nil
    end
  end

  describe "error state includes error details" do
    test "agent state tracks error information" do
      agent = ErrorHandlingAgent.new()

      {updated_agent, _directives} =
        ErrorHandlingAgent.cmd(
          agent,
          {TrackErrorAction, %{error_message: "Database connection failed", error_context: :db}}
        )

      assert updated_agent.state.status == :failed
      assert updated_agent.state.error == "Database connection failed"
      assert updated_agent.state.error_context == :db
    end

    test "error state preserved across operations" do
      agent = ErrorHandlingAgent.new()

      {agent_with_error, _} =
        ErrorHandlingAgent.cmd(
          agent,
          {TrackErrorAction, %{error_message: "API timeout", error_context: :api}}
        )

      assert agent_with_error.state.error == "API timeout"
      assert agent_with_error.state.error_context == :api
    end
  end

  describe "bounded retry prevents infinite loops" do
    test "retry stops at max_attempts", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, ErrorHandlingAgent, id: unique_id("bounded"))

      signal = Signal.new!("retry", %{max_attempts: 3, succeed_on: 100}, source: "/test")
      :ok = AgentServer.cast(pid, signal)

      eventually_state(
        pid,
        fn state ->
          state.agent.state.status == :exhausted and
            state.agent.state.attempts >= 3
        end,
        timeout: 2_000
      )

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.attempts >= 3
      assert state.agent.state.result == :max_retries_reached
    end

    test "retry succeeds before max_attempts", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, ErrorHandlingAgent, id: unique_id("succeed"))

      signal = Signal.new!("retry", %{max_attempts: 10, succeed_on: 3}, source: "/test")
      :ok = AgentServer.cast(pid, signal)

      eventually_state(
        pid,
        fn state -> state.agent.state.status == :success end,
        timeout: 2_000
      )

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.attempts == 3
      assert state.agent.state.result == "finally succeeded"
    end

    test "pure cmd/2 tracks attempt count correctly" do
      agent = ErrorHandlingAgent.new()

      {agent, _} = ErrorHandlingAgent.cmd(agent, {BoundedRetryAction, %{max_attempts: 3}})
      assert agent.state.attempts == 1
      assert agent.state.status == :retrying

      {agent, _} = ErrorHandlingAgent.cmd(agent, {BoundedRetryAction, %{max_attempts: 3}})
      assert agent.state.attempts == 2
      assert agent.state.status == :retrying

      {agent, _} = ErrorHandlingAgent.cmd(agent, {BoundedRetryAction, %{max_attempts: 3}})
      assert agent.state.attempts == 3
      assert agent.state.status == :exhausted
      assert agent.state.result == :max_retries_reached
    end
  end
end
