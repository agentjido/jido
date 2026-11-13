Code.require_file("audit.ex", __DIR__)

defmodule Jido.Examples.Applications.AuditTest do
  use Jido.Test.Case, async: false
  @moduletag :integration
  alias Jido.Plugin.Audit
  alias Jido.Signal
  alias Jido.Examples.Applications.Audit.Agent

  test "domain records commit with state, stay bounded, and exclude failed Flows", %{jido: jido} do
    {:ok, agent_server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Agent, id: unique_id("audit"))

    for operation <- [:publish, :update, :archive] do
      (
        assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
                 Jido.AgentServer.call(
                   agent_server,
                   turn_signal(%{operation: operation}, false)
                 )

        assert turn_result.status in [:committed, :waiting]
        committed = Jido.AgentServer.snapshot(agent_server).agent
      )

      assert committed.state.successes >= 1
    end

    committed = Jido.AgentServer.snapshot(agent_server).agent
    assert committed.state.successes == 3

    assert Enum.map(committed.state.audit.records, & &1.event) == [
             %{operation: :update},
             %{operation: :archive}
           ]

    assert Enum.all?(committed.state.audit.records, &(&1.outcome == :accepted))
    assert Enum.all?(committed.state.audit.records, &(&1.metadata.agent_id == committed.id))
    assert {:ok, committed.state.audit} == Jido.Test.AgentServer.ExampleRuntime.plugin_state(agent_server, Audit)
    before_failure = Jido.AgentServer.snapshot(agent_server)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: %Jido.Error.ExecutionError{}}} =
             Jido.AgentServer.call(agent_server, turn_signal(%{operation: :delete}, true))

    assert Jido.AgentServer.snapshot(agent_server) == before_failure

    assert Enum.map(Jido.AgentServer.snapshot(agent_server).agent.state.audit.records, & &1.event) ==
             [
               %{operation: :update},
               %{operation: :archive}
             ]
  end

  defp turn_signal(event, fail?) do
    Signal.new!(
      "examples.applications.audit.turn",
      %{event: event, fail?: fail?},
      source: "/test/audit"
    )
  end
end
