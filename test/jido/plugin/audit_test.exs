defmodule Jido.Plugin.AuditTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Audit

  defmodule RecordAction do
    use Jido.Action, name: "audit_plugin_record"

    @impl Jido.Action
    def run(%{event: event}, context) do
      state = %{context.agent_state | count: context.agent_state.count + 1}
      {:ok, state, [Audit.record(event, :accepted, metadata: %{source: :test})]}
    end
  end

  defmodule Agent do
    use Jido.Agent,
      name: "audit_plugin_agent",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      routes: [{"audit.record", RecordAction}],
      plugins: [{Audit, max_entries: 2}]
  end

  defmodule NonPortableAction do
    use Jido.Action, name: "audit_plugin_non_portable"

    @impl Jido.Action
    def run(_params, context) do
      {:ok, %{context.agent_state | count: 1},
       [Audit.record(:bad, :rejected, metadata: %{pid: self()})]}
    end
  end

  defmodule NonPortableAgent do
    use Jido.Agent,
      name: "audit_plugin_non_portable_agent",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      routes: [{"audit.bad", NonPortableAction}],
      plugins: [Audit]
  end

  test "commits bounded audit records with domain state", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, Agent, id: unique_id("audit"))

    for event <- [:one, :two, :three] do
      assert {:ok, _agent} = Server.call(pid, signal("audit.record", %{event: event}))
    end

    agent = Server.agent(pid)
    assert agent.state.count == 3
    assert Enum.map(agent.state.audit.records, & &1.event) == [:two, :three]
    assert Enum.all?(agent.state.audit.records, &Jido.Signal.ID.valid?(&1.id))
    assert Enum.all?(agent.state.audit.records, &(&1.metadata == %{source: :test}))
    assert {:ok, agent.state.audit} == Server.plugin_state(pid, Audit)
    assert Server.children(pid) == %{}
  end

  test "rejects non-portable audit data before commit", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, NonPortableAgent, id: unique_id("audit-portable"))

    assert {:error, %Jido.Error.ValidationError{}} = Server.call(pid, signal("audit.bad"))
    assert Server.agent(pid).state.count == 0
    assert Server.agent(pid).state.audit.records == []
  end
end
