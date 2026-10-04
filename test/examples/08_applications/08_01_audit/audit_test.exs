defmodule JidoTest.Examples.Applications.AuditTest do
  use JidoTest.Case, async: false

  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Audit
  alias Jido.Signal
  alias Jido.Examples.Applications.Audit.Agent

  test "domain records commit with state, stay bounded, and exclude failed Flows", %{jido: jido} do
    {:ok, agent_server} =
      Jido.start_agent(jido, Agent, id: unique_id("audit"), error_policy: :log_only)

    for operation <- [:publish, :update, :archive] do
      assert {:ok, committed} =
               Server.call(
                 agent_server,
                 turn_signal(%{operation: operation}, false)
               )

      assert committed.state.successes >= 1
    end

    committed = Server.agent(agent_server)
    assert committed.state.successes == 3

    assert Enum.map(committed.state.audit.records, & &1.event) == [
             %{operation: :update},
             %{operation: :archive}
           ]

    assert Enum.all?(committed.state.audit.records, &(&1.outcome == :accepted))
    assert Enum.all?(committed.state.audit.records, &(&1.metadata.agent_id == committed.id))
    assert {:ok, committed.state.audit} == Server.plugin_state(agent_server, Audit)
    assert Server.children(agent_server) == %{}

    before_failure = Server.snapshot(agent_server)

    assert {:error, %Jido.Action.Error.ExecutionFailureError{}} =
             Server.call(agent_server, turn_signal(%{operation: :delete}, true))

    assert Server.snapshot(agent_server) == before_failure

    assert Enum.map(Server.agent(agent_server).state.audit.records, & &1.event) == [
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
