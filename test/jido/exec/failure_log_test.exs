defmodule Jido.Exec.FailureLogTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  require Logger

  alias Jido.Joi

  @param "FAILURE-LOG-PARAM-SENTINEL"
  @secret "FAILURE-LOG-CONTEXT-SENTINEL"
  @literal "FAILURE-LOG-LITERAL-SENTINEL"
  @reason "FAILURE-LOG-REASON-SENTINEL"
  @context %{api_key: @secret}

  defmodule Boom do
    use Jido.Action, name: "failure_log_boom", schema: Joi.map()

    def run(_params, _context), do: {:error, "FAILURE-LOG-REASON-SENTINEL"}
  end

  defmodule Clause do
    use Jido.Action, name: "failure_log_clause", schema: Joi.map()

    def run(%{never: true}, _context), do: {:ok, %{}}
  end

  defmodule InvalidReturn do
    use Jido.Action, name: "failure_log_invalid_return", schema: Joi.map()

    def run(params, _context), do: params
  end

  defmodule Counter do
    use Jido.Action, name: "failure_log_counter", schema: Joi.map()

    def run(%{n: n, card: card}, _context), do: {:ok, %{n: n + 1, card: card}}
  end

  defmodule Loud do
    use Jido.Action, name: "failure_log_loud", schema: Joi.map()

    def run(_params, _context) do
      Logger.info("application info before failure")
      {:ok, _nested} = Jido.Exec.run(Counter, %{n: 0, card: "x"})
      Logger.warning("application warning after nested call")
      {:error, "failed"}
    end
  end

  defmodule LiteralFlow do
    use Jido.Flow, name: "failure_log_literal_flow"

    flow do
      step "a", action: Boom, params: %{card: "FAILURE-LOG-LITERAL-SENTINEL"}
      output result("a")
    end
  end

  defmodule ClauseStepFlow do
    use Jido.Flow, name: "failure_log_clause_step_flow"

    flow do
      step "a", action: Clause, params: %{card: input(:card)}
      output result("a")
    end
  end

  defmodule ClauseMapFlow do
    use Jido.Flow, name: "failure_log_clause_map_flow"

    flow do
      map "m", collection: input(:cards), action: Clause, params: %{card: item()}
      output %{r: result("m")}
    end
  end

  defmodule CollectFlow do
    use Jido.Flow, name: "failure_log_collect_flow"

    flow do
      map "m",
        collection: input(:cards),
        action: Boom,
        params: %{card: item()},
        on_error: :collect_errors

      output %{r: result("m")}
    end
  end

  defmodule ExhaustFlow do
    use Jido.Flow, name: "failure_log_exhaust_flow"

    flow do
      iterate "loop" do
        state Joi.object(%{n: Joi.integer(), card: Joi.string()}),
          initial: %{n: 0, card: input(:card)}

        action Counter
        params %{n: state(:n), card: state(:card)}
        update %{n: body_result(:n), card: body_result(:card)}
        while state(:n) < 100
        max_iterations 2
      end

      output %{r: result("loop")}
    end
  end

  defmodule InvalidReturnFlow do
    use Jido.Flow, name: "failure_log_invalid_return_flow"

    flow do
      step "a", action: InvalidReturn, params: %{card: input(:card)}
      output result("a")
    end
  end

  defmodule ReduceFlow do
    use Jido.Flow, name: "failure_log_reduce_flow"

    flow do
      reduce "r" do
        collection input(:card)
        initial %{}
        action Counter
        params %{n: item(), card: "x"}
      end

      output result("r")
    end
  end

  defmodule LiteralAgent do
    use Jido.Agent, name: "failure_log_agent"

    routes do
      signal_source "/failure_log"
      route "failure_log.flow", LiteralFlow, as: :flow
    end
  end

  defp assert_no_sentinel(log) do
    refute log =~ "Runnable failed"

    for sentinel <- [@param, @secret, @literal, @reason] do
      refute log =~ sentinel
    end
  end

  defp logged(work), do: capture_log([level: :debug], work)

  defp input(key \\ :card), do: %{key => @param}

  defp managed_failure(target, params) do
    runner = :"failure_log_runner_#{System.unique_integer([:positive])}"
    start_supervised!({Runic.Runner, name: runner})

    assert {:ok, _pid} = Jido.Test.Exec.RunnerHarness.start(runner, "run", target, params, @context)
    assert {:error, _error} = await_result(runner, "run", 200)
  end

  defp await_result(runner, id, attempts) do
    case Jido.Test.Exec.RunnerHarness.result(runner, id) do
      {:error, %{details: %{reason: :execution_active}}} when attempts > 0 ->
        Process.sleep(10)
        await_result(runner, id, attempts - 1)

      result ->
        result
    end
  end

  test "the capture sees Runic's line when a caller drives Runic directly" do
    workflow = Jido.Exec.compile!(Jido.Instruction.new!(target: Boom, params: %{card: @param}))

    log = logged(fn -> Runic.Workflow.execute(workflow, %{}) end)

    assert log =~ "Runnable failed"
    assert log =~ @param
  end

  test "Exec.run with an Action target logs no params or context" do
    log = logged(fn -> assert {:error, _} = Jido.Exec.run(Boom, input(), @context) end)
    assert_no_sentinel(log)
  end

  test "Jido.Test.Exec.RunnerHarness.start with an Action target logs no params" do
    assert_no_sentinel(logged(fn -> managed_failure(Boom, input()) end))
  end

  test "Exec.run with a Flow target logs no step literals" do
    log = logged(fn -> assert {:error, _} = Jido.Exec.run(LiteralFlow, %{}, @context) end)
    assert_no_sentinel(log)
  end

  test "Jido.Test.Exec.RunnerHarness.start with a Flow target logs no step literals" do
    assert_no_sentinel(logged(fn -> managed_failure(LiteralFlow, %{}) end))
  end

  test "a concurrent Flow failure logs no step literals" do
    log =
      logged(fn ->
        assert {:error, _} = Jido.Exec.run(ClauseMapFlow, %{cards: [@param]}, @context, max_concurrency: 2)
      end)

    assert_no_sentinel(log)
  end

  test "a FunctionClauseError in a Step logs no params or context" do
    log = logged(fn -> assert {:error, _} = Jido.Exec.run(ClauseStepFlow, input(), @context) end)
    assert_no_sentinel(log)
  end

  test "a FunctionClauseError in a Map logs no params or context" do
    log =
      logged(fn ->
        assert {:error, _} = Jido.Exec.run(ClauseMapFlow, %{cards: [@param]}, @context)
      end)

    assert_no_sentinel(log)
  end

  test "Iterate exhaustion logs no Iterate state" do
    log = logged(fn -> assert {:error, _} = Jido.Exec.run(ExhaustFlow, input(), @context) end)
    assert_no_sentinel(log)
  end

  test "an invalid Action return logs no returned value" do
    log =
      logged(fn -> assert {:error, _} = Jido.Exec.run(InvalidReturnFlow, input(), @context) end)

    assert_no_sentinel(log)
  end

  test "a non-enumerable Reduce collection logs no collection value" do
    log = logged(fn -> assert {:error, _} = Jido.Exec.run(ReduceFlow, input(), @context) end)
    assert_no_sentinel(log)
  end

  test "Agent.cmd logs no error reason or step literals" do
    agent = LiteralAgent.instantiate!(id: "failure-log-agent")
    signal = Jido.Signal.new!("failure_log.flow", %{}, source: "/failure_log")

    log = logged(fn -> assert {:error, _} = Jido.Agent.cmd(agent, signal, context: @context) end)
    assert_no_sentinel(log)
  end

  test "Exec.run logs no runtime failure details" do
    log = logged(fn -> assert {:error, _} = Jido.Exec.run(Boom, input(), @context) end)
    assert log == ""
  end

  test "Map collect_errors logs nothing" do
    log =
      logged(fn ->
        assert {:ok, %{r: [%{status: :error}]}} =
                 Jido.Exec.run(CollectFlow, %{cards: [@param]}, @context)
      end)

    assert log == ""
  end

  test "an Action keeps its own logs in Exec.run, including after a nested Action call" do
    log = logged(fn -> assert {:error, _} = Jido.Exec.run(Loud, %{}) end)

    assert log =~ "application info before failure"
    assert log =~ "application warning after nested call"
    refute log =~ "Runnable failed"
  end

  test "a telemetry handler keeps its logs in Exec.run" do
    id = "failure-log-telemetry-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      id,
      [:jido, :action, :stop],
      &__MODULE__.log_action_stop/4,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)

    log = logged(fn -> assert {:error, _} = Jido.Exec.run(Boom, %{}) end)

    assert log =~ "observed action stop"
  end

  test "Jido.Test.Exec.RunnerHarness.start keeps a caller's on_failed hook" do
    runner = :"failure_log_runner_#{System.unique_integer([:positive])}"
    start_supervised!({Runic.Runner, name: runner})
    test_pid = self()

    log =
      logged(fn ->
        assert {:ok, _pid} =
                 Jido.Test.Exec.RunnerHarness.start(runner, "run", Boom, input(), %{},
                   hooks: [on_failed: fn _runnable, _error, _state -> send(test_pid, :on_failed) end]
                 )

        assert_receive :on_failed, 2_000
        assert {:error, _} = await_result(runner, "run", 200)
      end)

    assert_no_sentinel(log)
  end

  def log_action_stop(_event, _measurements, _metadata, _config) do
    Logger.info("observed action stop")
  end
end
