defmodule JidoTest.Examples.Applications.AuditTest do
  use JidoTest.Case, async: false

  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Agent.Turn.Outcome
  alias Jido.Signal
  alias Jido.Signal.ID
  alias Jido.Examples.Applications.Audit.{Agent, Plugin, Runtime}

  test "a failed Flow keeps Agent state and exposes one runtime Outcome", %{
    jido: jido
  } do
    test_pid = self()

    policy = fn reason, %Outcome{} = outcome ->
      send(test_pid, {:audit_failure, reason, outcome})
      :continue
    end

    {:ok, agent_server} =
      Jido.start_agent(jido, Agent,
        id: unique_id("audit"),
        error_policy: policy
      )

    runtime = plugin_runtime(agent_server)

    success =
      Signal.new!(
        "audit.turn",
        %{event: %{operation: :publish}, fail?: false},
        source: "/test/audit"
      )

    assert {:ok, committed} = Server.call(agent_server, success)
    assert committed.state.successes == 1

    assert committed.state.audit.events == [
             %{event: %{operation: :publish}, outcome: :accepted}
           ]

    eventually(fn -> Runtime.events(runtime) == committed.state.audit.events end)

    failure =
      Signal.new!(
        "audit.turn",
        %{event: %{operation: :delete}, fail?: true},
        source: "/test/audit"
      )

    assert {:error, reason} = Server.call(agent_server, failure)
    assert Server.agent(agent_server).state == committed.state
    assert Runtime.events(runtime) == committed.state.audit.events

    assert_receive {:audit_failure, ^reason,
                    %Outcome{
                      status: :failed,
                      stage: :execute,
                      committed?: false,
                      state_version_before: 1,
                      state_version_after: nil
                    } = outcome}

    assert ID.valid?(outcome.id)
    assert outcome.source_signal.id == failure.id
    assert outcome.effective_signal.id == failure.id

    assert outcome.directives == %{
             total: 0,
             completed: 0,
             failed: 0,
             failed_index: nil,
             skipped: 0
           }
  end

  defp plugin_runtime(agent_server) do
    case Server.children(agent_server)[{:plugin, Plugin}] do
      %{pid: pid} when is_pid(pid) -> pid
      _child -> nil
    end
  end
end
