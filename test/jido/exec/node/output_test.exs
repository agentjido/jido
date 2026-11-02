defmodule Jido.Exec.Node.OutputTest do
  use ExUnit.Case, async: true

  alias Jido.Exec.{Fact, Frame}
  alias Jido.Exec.Node.Output
  alias Runic.Workflow
  alias Runic.Workflow.Invokable

  test "output hooks preserve failures and discard deferred changes" do
    node = Output.new(id: :output, name: "output", output: %{value: 1}, effect_order: [])
    owner = self()

    deferred = fn _event, _context ->
      {:apply,
       fn workflow ->
         send(owner, :applied)
         workflow
       end}
    end

    for {timing, error} <- [
          before_hooks: {:hook_error, :rejected},
          after_hooks: {:hook_error, {:hook_error, :rejected}}
        ] do
      workflow =
        Workflow.new()
        |> Workflow.add(node)
        |> Map.put(:before_hooks, %{node.hash => [deferred]})
        |> Map.put(timing, %{node.hash => [fn _event, _context -> {:error, :rejected} end]})

      {:ok, runnable} = Invokable.prepare(node, workflow, Fact.local_root(Frame.new(%{})))
      executed = Invokable.execute(node, runnable)

      assert executed.status == :failed
      assert executed.error == error
      assert executed.events == nil
      assert executed.result == nil
      assert executed.hook_apply_fns == nil
      refute_received :applied
    end
  end

  test "output hooks keep effects and apply changes in hook order" do
    node = Output.new(id: :output, name: "output", output: %{value: 1}, effect_order: ["step"])
    owner = self()

    hook = fn event, _context ->
      send(owner, {:hook, event.timing})

      {:apply,
       fn workflow ->
         send(owner, {:applied, event.timing})
         workflow
       end}
    end

    workflow =
      Workflow.new()
      |> Workflow.add(node)
      |> Map.put(:before_hooks, %{node.hash => [hook]})
      |> Map.put(:after_hooks, %{node.hash => [hook]})

    frame = Frame.put_result(Frame.new(%{}), "step", %{}, [:effect])
    {:ok, runnable} = Invokable.prepare(node, workflow, Fact.local_root(frame))
    executed = Invokable.execute(node, runnable)

    assert executed.status == :completed
    assert Fact.value(executed.result) == %{value: 1}
    assert executed.result.meta.jido.effects == [:effect]
    assert_receive {:hook, :before}
    assert_receive {:hook, :after}
    refute_received {:applied, _}

    Workflow.apply_runnable(workflow, executed)
    assert_receive {:applied, :before}
    assert_receive {:applied, :after}
  end
end
