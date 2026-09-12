defmodule Jido.AgentServer.WorkTest do
  use ExUnit.Case, async: true

  alias Jido.AgentServer.Work

  test "accepts only the result for the current work identity" do
    supervisor = start_supervised!(Task.Supervisor)

    work =
      Work.start(supervisor, "activation-1", :admission, fn -> {:ok, :accepted} end,
        turn_id: "turn-1",
        expected_version: 7
      )

    assert_receive {ref, %Work.Result{} = result}
    assert ref == work.task.ref
    assert {:ok, {:ok, :accepted}} = Work.result(work, ref, result)
    assert result.identity.activation_id == "activation-1"
    assert result.identity.kind == :admission
    assert result.identity.turn_id == "turn-1"
    assert result.identity.expected_version == 7
    assert :ok = Work.release(work)
  end

  test "rejects a result with a different work identity" do
    supervisor = start_supervised!(Task.Supervisor)
    gate = make_ref()
    owner = self()

    work =
      Work.start(supervisor, "activation-1", :directive, fn ->
        send(owner, {:started, self()})

        receive do
          ^gate -> :ok
        end
      end)

    assert_receive {:started, task_pid}

    stale_identity = %{work.identity | id: make_ref()}
    stale = %Work.Result{identity: stale_identity, value: :stale}
    assert :stale = Work.result(work, work.task.ref, stale)

    send(task_pid, gate)
    assert_receive {ref, %Work.Result{} = result}
    assert {:ok, :ok} = Work.result(work, ref, result)
    assert :ok = Work.release(work)
  end
end
