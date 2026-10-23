defmodule JidoTest.Examples.Runtime.DefinitionChangesTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.{Agent, AgentServer}
  alias Jido.Agent.{Diff, Directive}
  alias Jido.Examples.DefinitionChanges, as: Example

  test "pure evaluation returns a final Diff without changing the live Server", %{jido: jido} do
    {:ok, server} = JidoTest.ExampleRuntime.start_agent(jido, Example, id: unique_id())
    before = AgentServer.snapshot(server)
    assert {:ok, install} = Example.install_signal()
    assert {:ok, candidate, _} = Agent.cmd(before.agent, install)
    diff = Diff.between(before.agent, candidate)
    assert Diff.changed?(diff, :routes)
    refute Diff.changed?(diff, :agents)
    assert AgentServer.snapshot(server) == before

    assert {:ok, ^candidate, _} = AgentServer.call(server, install)
    assert :ok = AgentServer.await_ready(server)
    assert {:error, _} = AgentServer.call(server, install)
    assert AgentServer.snapshot(server) == %{agent: candidate, state_version: 1}
    work = Jido.Signal.new!("examples.runtime.definition.work.exact", %{}, source: "/examples")
    assert {:ok, %{state: %{selected: "exact"}}, []} = AgentServer.call(server, work)
    assert {:ok, remove} = Example.remove_signal()
    assert {:ok, _, _} = AgentServer.call(server, remove)
    assert {:ok, %{state: %{selected: "wildcard"}}, []} = AgentServer.call(server, work)
    assert :ok = Jido.stop_agent(jido, server)
  end

  test "cancelled edits produce an empty final Diff" do
    agent = Example.instantiate!(id: "diff")

    assert {:ok, ^agent, diff} =
             Agent.mutate(agent, [
               Directive.route_add("temporary", Example.Exact,
                 state: %{source: :output, path: []}
               ),
               Directive.route_remove("temporary")
             ])

    assert Diff.empty?(diff)
  end
end
