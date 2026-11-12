Code.require_file("definition_changes.ex", __DIR__)

defmodule Jido.Examples.Runtime.DefinitionChangesTest do
  use Jido.Test.Case, async: true
  @moduletag :integration

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.DefinitionChanges, as: Example
  import Jido.Test.Eventually

  test "a whole-definition upgrade keeps the Ref and replaces the PID", %{jido: jido} do
    agent = Example.V1.instantiate!(id: unique_id("definition-upgrade"), state: %{count: 2})
    {:ok, server} = Jido.start_agent(jido, agent)
    assert :ok = Server.await_ready(server)
    {:ok, ref} = Jido.agent_ref(jido, agent.id)
    {document, catalog} = Example.upgrade_input()

    assert {:ok, upgraded, []} =
             Server.upgrade(server, document, catalog: catalog, migrate: Example.Migrate)

    assert upgraded.module == Example.V2
    assert upgraded.vsn == 2
    assert upgraded.state == %{total: 12}

    replacement =
      eventually(fn ->
        case Jido.resolve_agent(jido, ref) do
          {:ok, pid} when pid != server -> pid
          _ -> nil
        end
      end)

    refute Process.alive?(server)
    assert :ok = Server.await_ready(replacement)
    assert %{agent: ^upgraded, state_version: 1} = Server.snapshot(replacement)

    assert {:ok, next, []} = Jido.call(jido, ref, Example.increment_signal())
    assert next.state == %{total: 13}
  end

  test "normal work changes state but not the definition" do
    agent = Example.V1.instantiate!(id: unique_id("fixed-definition"))
    definition = Jido.Agent.definition(agent)

    assert {:ok, changed, []} = Jido.Agent.cmd(agent, Example.increment_signal())
    assert changed.state == %{count: 1}
    assert Jido.Agent.definition(changed) == definition
  end
end
