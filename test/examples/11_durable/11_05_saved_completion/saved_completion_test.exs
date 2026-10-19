defmodule JidoTest.Examples.Durable.SavedCompletionTest do
  use JidoTest.Case, async: false
  @moduletag :example
  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Durable.SavedCompletion, as: Example
  alias JidoTest.Examples.Durable.{CompletionProbe, CompletionStorage}

  test "a saved completion survives a lost storage reply without repeating Flow work", c do
    start_supervised!({CompletionProbe, self()})
    persistence = {CompletionStorage, path: c.tmp_dir}
    id = unique_id("completion")

    assert {:ok, server} =
             Jido.start_agent(c.jido, Example,
               id: id,
               persistence: persistence,
               exec_opts: [hooks: [on_complete: fn _, _, _ -> CompletionProbe.completed() end]]
             )

    assert :ok = Server.await_ready(server)
    {:ok, request} = Example.request_signal(%{topic: "OTP"})
    pending = Server.submit(server, request)
    assert_receive {:completion_saved, _}, 5_000
    turn_id = Server.status(server).active.turn_id
    count = CompletionProbe.count()
    assert count > 0
    monitor = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^server, :killed}, 5_000
    :ok = CompletionProbe.release()

    restored =
      eventually(fn ->
        case Jido.whereis_agent(c.jido, id) do
          pid when is_pid(pid) and pid != server -> pid
          _ -> nil
        end
      end)

    assert :ok = Server.await_ready(restored)
    assert Server.agent(restored).state == %{report: "Report: OTP", completed: 1}
    assert Server.status(restored).durable_turn == %{id: turn_id, status: :completed}
    assert CompletionProbe.count() == count
    assert {:error, _} = Server.await(pending)

    # A repeated Signal is a new Turn. The lost caller handle is not a receipt API.
    assert {:ok, agent, []} = Server.call(restored, request)
    assert agent.state.completed == 2
    assert CompletionProbe.count() > count
    assert :ok = Server.hibernate(restored)
    assert {:ok, awake} = Jido.thaw(c.jido, Example, id, persistence: persistence)
    assert :ok = Server.await_ready(awake)
    assert Server.agent(awake) == agent
    assert :ok = Jido.stop_agent(c.jido, awake)
    assert Jido.agent_count(c.jido) == 0
  end
end
