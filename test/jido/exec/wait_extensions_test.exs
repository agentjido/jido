defmodule Jido.Exec.WaitExtensionsTest do
  use ExUnit.Case, async: true

  alias Jido.Exec.{Frame, Waits}
  alias Jido.Flow.Ref
  alias Runic.Workflow

  defmodule Approval do
    use Jido.Flow, name: "wait_extension_approval"

    flow do
      selection "decision" do
        await "approved", event: "approved", match: %{id: input(:id)}
        await "also_approved", event: "approved", match: %{id: input(:id)}
        timer "expired", after_ms: 1_000
      end

      output result("decision")
    end
  end

  defp waiting(target \\ Approval, execution_id \\ "execution", clock \\ 100) do
    {:ok, workflow} = Jido.Exec.compile(target)

    workflow
    |> Workflow.put_run_context(%{_global: Waits.context(%{}, execution_id, clock)})
    |> Workflow.react_until_satisfied(Frame.new(%{id: 7}))
  end

  defp candidate(id, at, order \\ 0) do
    %{
      input: %{id: id, event: "approved", payload: %{id: 7}},
      accepted_at: at,
      order: order
    }
  end

  test "host candidates resolve a wait through native replay without running successors" do
    workflow = waiting()
    [request] = Waits.pending(workflow)
    refute Map.has_key?(request, :node_hash)
    refute Map.has_key?(request, :input_id)
    assert Waits.next_deadline(workflow) == 1_100
    assert Waits.matches?(request, "approved", %{id: 7})
    refute Waits.matches?(request, "approved", %{id: 8})
    assert {:ok, resolved} = Waits.resolve(workflow, request.id, [candidate("one", 101)], 102)
    assert Waits.pending(resolved) == []
    assert Workflow.is_runnable?(resolved)
    restored = resolved |> Workflow.event_log() |> Workflow.from_events()
    assert {:ok, ^restored} = Waits.resolve(restored, request.id, [candidate("one", 101)], 103)

    assert {:ok, %{selected: "approved", value: %{id: 7}, input_id: "one"}} =
             restored |> Workflow.react_until_satisfied() |> Jido.Exec.result()
  end

  test "selection uses time, timer priority, receipt order, and option order" do
    workflow = waiting()
    [request] = Waits.pending(workflow)

    candidates = [
      candidate("later", 102, 0),
      candidate("second", 101, 2),
      candidate("first", 101, 1)
    ]

    assert {:ok, resolved} = Waits.resolve(workflow, request.id, candidates, 103)

    assert {:ok, %{input_id: "first"}} =
             resolved |> Workflow.react_until_satisfied() |> Jido.Exec.result()

    assert {:ok, resolved} = Waits.resolve(workflow, request.id, [candidate("tie", 1_100)], 1_100)

    assert {:ok, %{selected: "expired", value: %{fired_at: 1_100}, input_id: nil}} =
             resolved |> Workflow.react_until_satisfied() |> Jido.Exec.result()
  end

  test "future or unmatched candidates leave the wait open and malformed candidates fail" do
    workflow = waiting()
    [request] = Waits.pending(workflow)
    assert {:ok, ^workflow} = Waits.resolve(workflow, request.id, [candidate("future", 103)], 102)
    wrong = put_in(candidate("wrong", 101), [:input, :payload], %{id: 8})
    assert {:ok, ^workflow} = Waits.resolve(workflow, request.id, [wrong], 102)

    assert {:error, %{details: %{reason: :invalid_candidate}}} =
             Waits.resolve(workflow, request.id, [%{}], 102)

    assert {:error, %{details: %{reason: :stale_target}}} =
             Waits.resolve(workflow, "unknown", [], 102)

    assert {:error, %{details: %{reason: :invalid_clock}}} =
             Waits.resolve(workflow, request.id, [], -1)
  end

  test "wait IDs include execution scope even with equal direct inputs" do
    [first] = Approval |> waiting("first") |> Waits.pending()
    workflow = waiting(Approval, "second")
    [second] = Waits.pending(workflow)
    assert first.id != second.id
    assert first.execution_id == "first"
    assert second.execution_id == "second"

    assert {:error, %{details: %{reason: :stale_target}}} =
             Waits.resolve(workflow, first.id, [candidate("old", 101)], 102)
  end

  test "the host clock is read at opening and wait support does not force durable validation" do
    key = make_ref()
    Process.put(key, 123)
    clock = fn -> Process.get(key) end
    context = Waits.context(%{custom: true}, "clock", clock)
    assert context.custom
    refute Map.get(context, :__jido_exec_durable__, false)
    Process.put(key, 321)
    {:ok, workflow} = Jido.Exec.compile(Approval)

    workflow =
      workflow
      |> Workflow.put_run_context(%{_global: context})
      |> Workflow.react_until_satisfied(Frame.new(%{id: 7}))

    [request] = Waits.pending(workflow)
    assert request.opened_at == 321
    assert Waits.next_deadline(workflow) == 1_321
    assert Workflow.from_events(Workflow.event_log(workflow)).run_context == %{}
    Process.delete(key)
  end

  test "resolution invokes neither before nor after hooks" do
    workflow = waiting()
    owner = self()

    hook = fn _, workflow, _ ->
      send(owner, :unexpected_hook)
      workflow
    end

    workflow =
      workflow
      |> Workflow.attach_before_hook("decision", hook)
      |> Workflow.attach_after_hook("decision", fn _, _, _ -> raise "must not run" end)

    [request] = Waits.pending(workflow)
    assert {:ok, resolved} = Waits.resolve(workflow, request.id, [candidate("one", 101)], 102)
    refute_received :unexpected_hook
    assert Waits.pending(resolved) == []

    assert {:ok, %{selected: "approved"}} =
             resolved |> Workflow.react_until_satisfied() |> Jido.Exec.result()
  end

  test "an in-memory host can resolve local values without durable portability checks" do
    flow =
      Jido.Flow.new!(%{
        name: "local_wait",
        components: [%{kind: :await, name: "message", event: "message"}],
        output: Ref.result("message")
      })

    {:ok, workflow} = Jido.Exec.compile(flow)

    workflow =
      workflow
      |> Workflow.put_run_context(%{_global: Waits.context(%{}, "local", 100)})
      |> Workflow.react_until_satisfied(Jido.Exec.Fact.local_root(Frame.new(%{})))

    [request] = Waits.pending(workflow)
    pid = self()

    candidate = %{
      input: %{id: "local", event: "message", payload: %{pid: pid}},
      accepted_at: 101,
      order: 0
    }

    assert {:ok, workflow} = Waits.resolve(workflow, request.id, [candidate], 101)

    assert {:ok, %{pid: ^pid}} =
             workflow |> Workflow.react_until_satisfied() |> Jido.Exec.result()
  end

  test "independent waits retain partial joins through replay" do
    flow =
      Jido.Flow.new!(%{
        name: "parallel_wait_extensions",
        components: [
          %{kind: :await, name: "left", event: "left"},
          %{kind: :await, name: "right", event: "right"}
        ],
        output: %{left: Ref.result("left"), right: Ref.result("right")}
      })

    workflow = waiting(flow)
    [left, right] = Waits.pending(workflow)

    event = fn name, value ->
      %{input: %{id: name, event: name, payload: %{value: value}}, accepted_at: 101, order: 0}
    end

    assert {:ok, workflow} = Waits.resolve(workflow, left.id, [event.("left", 1)], 101)

    workflow =
      workflow
      |> Workflow.react_until_satisfied()
      |> Workflow.event_log()
      |> Workflow.from_events()

    assert Waits.pending(workflow) == [right]
    assert {:ok, workflow} = Waits.resolve(workflow, right.id, [event.("right", 2)], 102)

    assert {:ok, %{left: %{value: 1}, right: %{value: 2}}} =
             workflow |> Workflow.react_until_satisfied() |> Jido.Exec.result()
  end
end
