defmodule Jido.Exec.Node.LoopTest do
  use ExUnit.Case, async: true

  alias Jido.Exec
  alias Jido.Exec.Frame
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Runic.Workflow

  defmodule Sum do
    use Jido.Action, name: "loop_test_sum"

    @impl true
    def run(%{acc: acc, item: item}, _context),
      do: {:ok, %{total: acc.total + item}, [{:added, item}]}
  end

  test "Reduce iteration facts do not copy the Flow frame or collection" do
    flow =
      Flow.new!(%{
        name: "loop_fact_size",
        components: [
          %{
            kind: :reduce,
            name: "sum",
            collection: Ref.input(:items),
            initial: %{total: 0},
            action: Sum,
            params: %{acc: Ref.accumulator(), item: Ref.item()}
          }
        ],
        output: Ref.result("sum")
      })

    input = %{items: [1, 2, 3], padding: Enum.to_list(1..1_000)}

    workflow =
      flow
      |> Exec.compile!()
      |> Workflow.put_run_context(%{_global: %{}})
      |> Workflow.react_until_satisfied(Workflow.Fact.new(value: Frame.new(input)))

    loop_values =
      workflow
      |> Workflow.facts()
      |> Enum.map(& &1.value)
      |> Enum.filter(&(is_tuple(&1) and elem(&1, 0) == :jido_reduce))

    assert length(loop_values) == 4
    assert Enum.all?(loop_values, &(:erlang.external_size(&1) < 200))

    assert Exec.run(flow, input) ==
             {:ok, %{total: 6}, [{:added, 1}, {:added, 2}, {:added, 3}]}
  end
end
