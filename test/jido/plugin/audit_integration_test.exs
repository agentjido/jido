defmodule Jido.Plugin.AuditIntegrationTest do
  use Jido.Test.Case, async: true

  alias Jido.AgentServer
  alias Jido.Plugin.Audit

  defmodule RecordAction do
    use Jido.Action,
      name: "audit_integration_record"

    @impl Jido.Action
    def run(%{event: event}, context) do
      state = %{context.agent_state | count: context.agent_state.count + 1}
      {:ok, state, [Audit.record(event, :accepted, metadata: %{source: :test})]}
    end
  end

  defmodule Agent do
    use Jido.Agent, name: "audit_integration_agent", plugins: [{Audit, %{max_entries: 2}}]

    state do
      schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end

    routes do
      route "audit.record", RecordAction
    end
  end

  test "AgentServer commits valid Audit state and rejects an invalid record atomically", %{
    jido: jido
  } do
    {:ok, server} =
      Jido.Test.AgentServer.Assertions.start_agent(jido, Agent, id: unique_id("audit"))

    for event <- [:one, :two, :three] do
      assert {:ok, _agent, _directives} =
               AgentServer.call(server, signal("audit.record", %{event: event}))
    end

    committed = Jido.Test.AgentServer.Assertions.committed(server)
    assert committed.agent.state.count == 3
    assert Enum.map(committed.agent.state.audit.records, & &1.event) == [:two, :three]
    assert {:ok, committed.agent.state.audit} == AgentServer.plugin_state(server, Audit)

    assert {:error, %Jido.Error.ValidationError{details: %{path: [:record, :event]}}} =
             AgentServer.call(server, signal("audit.record", %{event: <<5::3>>}))

    assert Jido.Test.AgentServer.Assertions.committed(server) == committed
  end
end
