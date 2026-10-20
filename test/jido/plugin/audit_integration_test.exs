defmodule Jido.Plugin.AuditIntegrationTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer
  alias Jido.Plugin.Audit

  defmodule RecordAction do
    use Jido.Action, name: "audit_integration_record"

    @impl Jido.Action
    def run(%{event: event}, context) do
      state = %{context.agent_state | count: context.agent_state.count + 1}
      {:ok, state, [Audit.record(event, :accepted, metadata: %{source: :test})]}
    end
  end

  defmodule Agent do
    use Jido.Agent, name: "audit_integration_agent"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
      plugin Audit, config: %{max_entries: 2}
    end

    routes do
      route "audit.record", RecordAction
    end
  end

  test "AgentServer commits valid Audit state and rejects an invalid record atomically", %{
    jido: jido
  } do
    {:ok, server} =
      JidoTest.AgentServerAssertions.start_agent(jido, Agent, id: unique_id("audit"))

    for event <- [:one, :two, :three] do
      assert {:ok, _agent, _directives} =
               AgentServer.call(server, signal("audit.record", %{event: event}))
    end

    committed = JidoTest.AgentServerAssertions.committed(server)
    assert committed.agent.state.count == 3
    assert Enum.map(committed.agent.state.audit.records, & &1.event) == [:two, :three]
    assert {:ok, committed.agent.state.audit} == AgentServer.plugin_state(server, Audit)

    assert {:error, %Jido.Error.ValidationError{details: %{path: [:record, :event]}}} =
             AgentServer.call(server, signal("audit.record", %{event: <<5::3>>}))

    assert JidoTest.AgentServerAssertions.committed(server) == committed
  end
end
