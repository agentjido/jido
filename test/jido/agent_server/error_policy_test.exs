defmodule JidoTest.AgentServer.ErrorPolicyTest do
  use JidoTest.Case, async: true

  @moduletag :capture_log

  alias Jido.Agent.Directive
  alias Jido.AgentServer.{ErrorPolicy, Options, State}

  defmodule TestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "error_policy_test_agent",
      schema: [
        counter: [type: :integer, default: 0]
      ]
  end

  defp build_state(error_policy, jido \\ :test_jido) do
    agent = TestAgent.new()

    opts_map = %{
      agent: agent,
      id: "error-policy-test-agent",
      error_policy: error_policy,
      jido: jido
    }

    {:ok, opts} = Options.new(opts_map)

    {:ok, state} = State.from_options(opts, agent.__struct__, agent)
    state
  end

  defp build_error_directive(message, context \\ :test) do
    error = Jido.Error.validation_error(message)
    %Directive.Error{error: error, context: context}
  end

  describe "log_only policy" do
    test "logs error and returns ok" do
      state = build_state(:log_only)
      directive = build_error_directive("Something went wrong")

      assert {:ok, ^state} = ErrorPolicy.handle(directive, state)
    end

    test "includes context in log" do
      state = build_state(:log_only)
      directive = build_error_directive("Error message", :validation)

      assert {:ok, ^state} = ErrorPolicy.handle(directive, state)
    end
  end

  describe "stop_on_error policy" do
    test "returns stop tuple with error" do
      state = build_state(:stop_on_error)
      error = Jido.Error.validation_error("Fatal error")
      directive = %Directive.Error{error: error, context: :fatal}

      assert {:stop, {:agent_error, ^error}, ^state} = ErrorPolicy.handle(directive, state)
    end
  end

  describe "emit_signal policy" do
    test "emits error signal via dispatch config", %{jido: jido} do
      state = build_state({:emit_signal, {:logger, level: :error}}, jido)
      directive = build_error_directive("Emittable error")

      assert {:ok, ^state} = ErrorPolicy.handle(directive, state)
    end
  end

  describe "max_errors policy" do
    test "continues until max errors reached" do
      state = build_state({:max_errors, 3})
      directive = build_error_directive("Error")

      assert state.error_count == 0

      {:ok, state} = ErrorPolicy.handle(directive, state)
      assert state.error_count == 1

      {:ok, state} = ErrorPolicy.handle(directive, state)
      assert state.error_count == 2

      {:stop, {:max_errors_exceeded, 3}, state} = ErrorPolicy.handle(directive, state)
      assert state.error_count == 3
    end

    test "increments error count before max" do
      state = build_state({:max_errors, 5})
      directive = build_error_directive("Warning error")

      {:ok, new_state} = ErrorPolicy.handle(directive, state)
      assert new_state.error_count == 1
    end
  end

  describe "custom function policy" do
    test "calls custom function with error and state", %{jido: jido} do
      test_pid = self()

      custom_policy = fn error_directive, state ->
        send(test_pid, {:custom_policy_called, error_directive, state})
        {:ok, state}
      end

      state = build_state(custom_policy, jido)
      directive = build_error_directive("Custom handled")

      assert {:ok, ^state} = ErrorPolicy.handle(directive, state)
      assert_receive {:custom_policy_called, ^directive, ^state}
    end

    test "allows custom function to return stop", %{jido: jido} do
      custom_policy = fn _error_directive, state ->
        {:stop, :custom_stop_reason, state}
      end

      state = build_state(custom_policy, jido)
      directive = build_error_directive("Stop me")

      assert {:stop, :custom_stop_reason, ^state} = ErrorPolicy.handle(directive, state)
    end

    test "allows custom function to modify state", %{jido: jido} do
      custom_policy = fn _error_directive, state ->
        new_state = State.increment_error_count(state)
        {:ok, new_state}
      end

      state = build_state(custom_policy, jido)
      directive = build_error_directive("Modify state")

      {:ok, new_state} = ErrorPolicy.handle(directive, state)
      assert new_state.error_count == 1
    end

    test "handles custom function crash gracefully" do
      custom_policy = fn _error_directive, _state ->
        raise "Policy crashed!"
      end

      state = build_state(custom_policy)
      directive = build_error_directive("Crash me")

      assert {:ok, ^state} = ErrorPolicy.handle(directive, state)
    end

    test "handles custom function throw gracefully" do
      custom_policy = fn _error_directive, _state ->
        throw(:policy_throw)
      end

      state = build_state(custom_policy)
      directive = build_error_directive("Throw me")

      assert {:ok, ^state} = ErrorPolicy.handle(directive, state)
    end

    test "handles invalid return from custom function" do
      custom_policy = fn _error_directive, _state ->
        :invalid_return
      end

      state = build_state(custom_policy)
      directive = build_error_directive("Invalid return")

      assert {:ok, ^state} = ErrorPolicy.handle(directive, state)
    end
  end

  describe "error details logging" do
    test "includes details in log when present" do
      state = build_state(:log_only)
      error = Jido.Error.execution_error("Boom", details: %{reason: :timeout})
      directive = %Directive.Error{error: error, context: :test}

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, ^state} = ErrorPolicy.handle(directive, state)
        end)

      assert log =~ "Boom"
      assert log =~ "timeout"
    end

    test "includes details in max_errors warning log before the threshold" do
      state = build_state({:max_errors, 3})
      error = Jido.Error.execution_error("Boom", reason: :timeout)
      directive = %Directive.Error{error: error, context: :test}

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, new_state} = ErrorPolicy.handle(directive, state)
          assert new_state.error_count == 1
        end)

      assert log =~ "Boom"
      assert log =~ "timeout"
    end

    test "omits details from log when empty" do
      state = build_state(:log_only)
      error = Jido.Error.execution_error("Boom")
      directive = %Directive.Error{error: error, context: :test}

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, ^state} = ErrorPolicy.handle(directive, state)
        end)

      assert log =~ "Boom"
      refute log =~ "%{"
    end
  end

  describe "unknown policy" do
    test "falls back to logging", %{jido: jido} do
      agent = TestAgent.new()
      {:ok, opts} = Options.new(%{agent: agent, id: "unknown-policy-agent", jido: jido})
      {:ok, state} = State.from_options(opts, agent.__struct__, agent)
      state = %{state | error_policy: :unknown_policy}

      directive = build_error_directive("Unknown policy error")

      assert {:ok, ^state} = ErrorPolicy.handle(directive, state)
    end
  end
end
