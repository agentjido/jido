defmodule JidoTest.System.ActionFlow.ExecTest do
  use ExUnit.Case, async: false

  @moduletag :system

  alias Jido.Exec
  alias Jido.Instruction

  defmodule MathFlow do
    use Jido.Flow, name: "system_math_flow"

    alias Jido.Test.Action.Fixtures.Actions.{Add, Multiply}

    flow do
      step "add", action: Add, params: %{value: input(:value), amount: 1}

      step "multiply",
        action: Multiply,
        params: %{value: result("add", :value), amount: 2}

      output result("multiply")
    end
  end

  test "one ready Flow runs through each public target form and releases its tasks" do
    baseline = task_children()
    flow = MathFlow.flow()
    instruction = Instruction.new!(target: MathFlow, params: %{value: 3})

    assert {:ok, ^flow} = Jido.Flow.validate(flow)
    assert Exec.run(flow, %{value: 3}) == {:ok, %{value: 8}}
    assert_task_children_return_to(baseline)

    assert Exec.run(MathFlow, %{value: 3}) == {:ok, %{value: 8}}
    assert_task_children_return_to(baseline)

    assert Exec.run(instruction) == {:ok, %{value: 8}}
    assert_task_children_return_to(baseline)
  end

  defp assert_task_children_return_to(expected, attempts \\ 50)
  defp assert_task_children_return_to(expected, 0), do: assert(task_children() == expected)

  defp assert_task_children_return_to(expected, attempts) do
    if task_children() == expected do
      :ok
    else
      Process.sleep(10)
      assert_task_children_return_to(expected, attempts - 1)
    end
  end

  defp task_children do
    Jido.Exec.TaskSupervisor
    |> Task.Supervisor.children()
    |> MapSet.new()
  end
end
