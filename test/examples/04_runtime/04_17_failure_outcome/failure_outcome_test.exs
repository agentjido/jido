defmodule JidoTest.Examples.Runtime.FailureOutcomeTest do
  use JidoTest.Case, async: false

  @moduletag :example

  alias Jido.Agent.Directive.Error, as: ErrorDirective
  alias Jido.Agent.Turn.Outcome
  alias Jido.AgentServer
  alias Jido.AgentServer.Signal.Error, as: ErrorSignal
  alias Jido.Examples.FailureOutcome

  test "a continuing policy observes both sides of the commit boundary", %{jido: jido} do
    observer = self()

    policy = fn reason, outcome ->
      send(observer, {:failure_outcome, reason, outcome})
      :continue
    end

    {:ok, server} =
      Jido.start_agent(jido, FailureOutcome,
        id: unique_id("failure-outcome"),
        error_policy: policy
      )

    {:ok, reject} = FailureOutcome.reject_signal(%{reason: "invalid"})
    assert {:error, precommit_error} = AgentServer.call(server, reject)

    assert_receive {:failure_outcome, ^precommit_error,
                    %Outcome{
                      status: :failed,
                      stage: :execute,
                      committed?: false,
                      state_version_before: 0,
                      state_version_after: nil
                    }}

    assert %{state_version: 0, agent: %{state: %{accepted: []}}} = AgentServer.snapshot(server)

    {:ok, report} = FailureOutcome.report_signal(%{name: "saved"})
    assert {:ok, committed} = AgentServer.call(server, report)
    assert committed.state.accepted == ["saved"]

    assert_receive {:failure_outcome, {:reported_error, :notification, reported_error},
                    %Outcome{
                      status: :failed,
                      stage: :directive,
                      committed?: true,
                      state_version_before: 0,
                      state_version_after: 1,
                      directives: %{
                        total: 1,
                        completed: 0,
                        failed: 1,
                        failed_index: 0,
                        skipped: 0
                      }
                    }}

    assert %Jido.Error.ExecutionError{} = reported_error

    assert %ErrorDirective{context: :notification} =
             Jido.Agent.Directive.error(reported_error, :notification)

    eventually(fn -> AgentServer.status(server).phase == :idle end)
    assert Process.alive?(server)
    assert AgentServer.agent(server) == committed
  end

  test "the stopping policy terminates the Agent after a failure", %{jido: jido} do
    {:ok, server} =
      Jido.start_agent(jido, FailureOutcome,
        id: unique_id("stopping-policy"),
        error_policy: :stop_on_error,
        restart: :temporary
      )

    monitor = Process.monitor(server)
    {:ok, reject} = FailureOutcome.reject_signal(%{reason: "stop"})
    assert {:error, _reason} = AgentServer.call(server, reject)

    assert_receive {:DOWN, ^monitor, :process, ^server, {:shutdown, {:agent_error, _reason}}},
                   2_000
  end

  test "the emitted-Signal policy publishes bounded failure data", %{jido: jido} do
    {:ok, server} =
      Jido.start_agent(jido, FailureOutcome,
        id: unique_id("emitted-policy"),
        error_policy: {:emit_signal, {:pid, target: self()}}
      )

    {:ok, reject} = FailureOutcome.reject_signal(%{reason: "publish"})
    assert {:error, reason} = AgentServer.call(server, reject)

    assert_receive {:signal, signal}, 1_000
    assert signal.type == ErrorSignal.type()
    assert signal.data.stage == :execute
    refute signal.data.committed?
    assert signal.data.error == Jido.Error.to_map(reason)
    assert signal.data.agent_id == AgentServer.agent(server).id
  end
end
