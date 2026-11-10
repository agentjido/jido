defmodule Jido.Exec.Node.SingleOutputTest do
  use ExUnit.Case, async: true

  alias Jido.Exec.{Fact, Frame}
  alias Jido.Exec.Node.Input
  alias Jido.Flow.Ref
  alias Runic.Workflow
  alias Runic.Workflow.Invokable

  test "Flow input nodes participate in native batches after reconstruction" do
    node = Input.new(id: :input, name: "input", component: "child", params: Ref.input(nil))
    batch = Runic.batch(node, name: "inputs")
    workflow = Workflow.new() |> Workflow.add(batch)
    rebuilt = workflow |> Workflow.build_log() |> Workflow.from_log()
    frames = Enum.map([%{value: 1}, %{value: 2}], &Frame.new/1)
    {completed, observation} = Workflow.execute(rebuilt, frames)

    assert observation.quiescent?
    assert [id] = Runic.Workflow.Batch.invocations(completed, batch)
    assert {:ok, outcomes} = Runic.Workflow.Batch.outcomes(completed, batch, id)
    assert Enum.all?(outcomes, &(&1.status == :completed))
    assert Enum.map(outcomes, & &1.value) == Enum.map(frames, &Frame.nest(&1, elem(&1, 2)))
  end

  test "Flow input hooks run before resolution and after successful local output" do
    node = Input.new(id: :input, name: "input", component: "child", params: Ref.input(nil))
    owner = self()

    hook = fn event, _context ->
      send(owner, {:hook, event.timing})
      :ok
    end

    workflow =
      Workflow.new()
      |> Workflow.add(node)
      |> Map.put(:before_hooks, %{node.hash => [hook]})
      |> Map.put(:after_hooks, %{node.hash => [hook]})

    params = %{owner: self(), reference: make_ref()}
    frame = Frame.new(params)
    {:ok, runnable} = Invokable.prepare(node, workflow, Fact.local_root(frame))
    executed = Invokable.execute(node, runnable)

    assert executed.status == :completed
    assert Fact.value(executed.result) == Frame.nest(frame, params)
    assert executed.result.meta.jido.identity_mode == :local
    assert_receive {:hook, :before}
    assert_receive {:hook, :after}
  end
end
