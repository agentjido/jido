defmodule JidoTest.Examples.Applications.CoordinatorTest do
  use JidoTest.Case, async: false

  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Signal
  alias Jido.Examples.Applications.Coordinator.Agent

  test "one Flow turn commits delegation state before ordered child work", %{jido: jido} do
    {:ok, parent} = Jido.start_agent(jido, Agent, id: unique_id("coordinator"))

    signal =
      Signal.new!(
        "coordinator.delegate",
        %{task: :research, test: self()},
        source: "/test/coordinator"
      )

    assert {:ok, committed} = Server.call(parent, signal, 5_000)
    assert committed.state.delegations == 1
    assert committed.state.history == [%{kind: :delegation, task: :research}]

    child =
      eventually(fn ->
        case Server.children(parent)[:worker] do
          %{kind: :agent, pid: pid} = child when is_pid(pid) -> child
          _child -> nil
        end
      end)

    assert_receive {:worker_handled, :research}
    eventually(fn -> Server.agent(child.pid).state.jobs == [:research] end)
    eventually(fn -> Server.agent(parent).state.replies == 1 end)
    eventually(fn -> Server.agent(parent).state.timeouts == 1 end)
    eventually(fn -> Server.agent(parent).state.child_starts == 1 end)
    assert Server.agent(parent).state.history == committed.state.history
  end
end
