defmodule JidoTest.AgentServer.WaitHostTest do
  use ExUnit.Case, async: true

  alias Jido.AgentServer.WaitHost
  alias Jido.Exec.{Frame, Waits}
  alias Runic.Workflow

  defmodule Approval do
    use Jido.Flow, name: "host_policy_approval"

    flow do
      selection "decision" do
        await "approved", event: "approved", match: %{id: input(:id)}
        timer "expired", after_ms: 1_000
      end

      output result("decision")
    end
  end

  defp waiting do
    {:ok, workflow} = Jido.Exec.compile(Approval)

    workflow
    |> Workflow.put_run_context(%{_global: Waits.context(%{}, "execution", 100)})
    |> Workflow.react_until_satisfied(Frame.new(%{id: 7}))
  end

  defp input(workflow, id \\ "one") do
    [request] = Waits.pending(workflow)
    %{id: id, event: "approved", payload: %{id: 7}, wait_id: request.id}
  end

  test "accepted input survives replay, with equal retries inert and conflicting IDs rejected" do
    workflow = waiting()
    event = input(workflow)
    assert {:ok, accepted} = WaitHost.accept(workflow, event, 101)
    assert Waits.pending(accepted) == Waits.pending(workflow)
    accepted = accepted |> Workflow.event_log() |> Workflow.from_events()
    assert {:ok, ^accepted} = WaitHost.accept(accepted, event, 102)

    assert {:error, %{details: %{reason: :conflicting_input_id}}} =
             WaitHost.accept(accepted, %{event | payload: %{id: 8}}, 102)

    assert {:ok, resolved} = WaitHost.resolve(accepted, 102)
    assert Waits.pending(resolved) == []
    assert Workflow.is_runnable?(resolved)
    assert {:ok, ^resolved} = WaitHost.resolve(resolved, 103)

    assert {:ok, %{input_id: "one"}} =
             resolved |> Workflow.react_until_satisfied() |> Jido.Exec.result()
  end

  test "clock rollback cannot put a later accepted event before an earlier event" do
    workflow = waiting()
    assert {:ok, workflow} = WaitHost.accept(workflow, input(workflow, "first"), 200)
    assert {:ok, workflow} = WaitHost.accept(workflow, input(workflow, "second"), 150)
    assert {:ok, workflow} = WaitHost.resolve(workflow, 151)

    assert {:ok, %{input_id: "first", accepted_at: 200}} =
             workflow |> Workflow.react_until_satisfied() |> Jido.Exec.result()
  end

  test "the host rejects stale, unmatched, malformed, and non-portable input" do
    workflow = waiting()
    event = input(workflow)

    assert {:error, %{details: %{reason: :stale_target}}} =
             WaitHost.accept(workflow, %{event | wait_id: "old"}, 101)

    assert {:error, %{details: %{reason: :unmatched_input}}} =
             WaitHost.accept(workflow, %{event | payload: %{id: 8}}, 101)

    assert {:error, %{details: %{reason: :invalid_input}}} =
             WaitHost.accept(workflow, Map.put(event, :extra, true), 101)

    assert {:error, _} = WaitHost.accept(workflow, %{event | payload: %{id: 7, pid: self()}}, 101)
    assert {:error, _} = WaitHost.accept(workflow, event, -1)
    assert {:error, %{details: %{reason: :invalid_clock}}} = WaitHost.resolve(workflow, -1)
  end

  test "the production host supplies a current clock and durable validation" do
    context = WaitHost.context(%{custom: true}, "host", nil)
    assert context.custom
    assert context.__jido_exec_durable__
    assert is_function(context.__jido_wait_host__.clock, 0)
    before = System.system_time(:millisecond)
    assert context.__jido_wait_host__.clock.() >= before
  end

  test "the input limit rejects new receipts but permits equal retries" do
    workflow = waiting()
    event = input(workflow)

    full =
      Enum.reduce(1..1_024, workflow, fn index, current ->
        {:ok, next} = WaitHost.accept(current, %{event | id: Integer.to_string(index)}, 101)
        next
      end)

    assert {:ok, ^full} = WaitHost.accept(full, %{event | id: "1"}, 102)

    assert {:error, %{details: %{reason: :input_limit}}} =
             WaitHost.accept(full, %{event | id: "overflow"}, 102)
  end
end
