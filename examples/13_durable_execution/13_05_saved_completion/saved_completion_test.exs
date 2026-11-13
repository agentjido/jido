Code.require_file("saved_completion.ex", __DIR__)
Code.require_file("../support/durable_completion_probe.exs", __DIR__)

defmodule Jido.Examples.Durable.SavedCompletionTest do
  use Jido.Test.Case, async: false
  @moduletag :integration

  @moduletag :tmp_dir
  alias Jido.Examples.Durable.SavedCompletion, as: Example
  alias Jido.Test.Examples.Durable.{CompletionProbe, CompletionStorage}

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

    assert :ok = Jido.AgentServer.await_ready(server)
    {:ok, request} = Example.request_signal(%{topic: "OTP"})
    pending = Jido.AgentServer.submit(server, request)
    assert_receive {:completion_saved, _}, 5_000
    turn_id = Jido.AgentServer.status(server).active_turn_id
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

    assert :ok = Jido.AgentServer.await_ready(restored)

    assert Jido.AgentServer.snapshot(restored).agent.state == %{
             report: "Report: OTP",
             completed: 1
           }

    assert %Jido.AgentServer.Status{work_state: :idle, active_turn_id: nil} =
             Jido.AgentServer.status(restored)

    assert is_binary(turn_id)
    assert CompletionProbe.count() == count
    assert {:error, _} = Jido.AgentServer.await(pending)

    (
      # A repeated Signal is a new Turn. The lost caller handle is not a receipt API.
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(restored, request)

      assert turn_result.status in [:committed, :waiting]
      agent = Jido.AgentServer.snapshot(restored).agent
    )

    assert agent.state.completed == 2
    assert CompletionProbe.count() > count
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Jido.AgentServer.stop(restored)
    assert {:ok, awake} = Jido.thaw(c.jido, Example, id, persistence: persistence)
    assert :ok = Jido.AgentServer.await_ready(awake)
    assert Jido.AgentServer.snapshot(awake).agent == agent
    assert :ok = Jido.stop_agent(c.jido, awake)
    assert Jido.resident_agent_count(c.jido) == 0
  end
end
