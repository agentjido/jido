defmodule Jido.Exec.Node.ChoiceTest do
  use Covenant.Case, component: "jido_action.execution", async: true

  alias Jido.Exec
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias JidoActionTest.Fixtures.Actions.Add

  @tag obligation: "jido_action.execution.I17"
  test "an option named fallback remains separate from the default branch" do
    for {condition, amount} <- [{true, 100}, {false, -10}], concurrency <- [1, 4] do
      flow =
        Flow.new!(%{
          name: "fallback_option",
          components: [
            %{
              kind: :choice,
              name: "route",
              options: [
                %{
                  name: "fallback",
                  condition: condition,
                  action: Add,
                  params: %{value: 2, amount: 100}
                }
              ],
              fallback: %{action: Add, params: %{value: 2, amount: -10}}
            }
          ],
          output: Ref.result("route")
        })

      assert Exec.run(flow, %{}, %{}, max_concurrency: concurrency) ==
               {:ok, %{value: 2 + amount}}

      workflow =
        flow
        |> Exec.compile!()
        |> Runic.Workflow.build_log()
        |> Runic.Workflow.from_log()
        |> Runic.Workflow.put_run_context(%{_global: %{}})
        |> Runic.Workflow.react_until_satisfied(
          Runic.Workflow.Fact.new(value: Jido.Exec.Frame.new(%{})),
          scheduler_policies: [{:default, %{on_failure: :halt}}]
        )

      assert Exec.result(workflow) == {:ok, %{value: 2 + amount}}
    end
  end

  @tag obligation: "jido_action.execution.I17"
  test "Choice uses Runic Conditions and selects the first matching branch" do
    flow =
      Flow.new!(%{
        name: "choice",
        components: [
          %{
            kind: :choice,
            name: "route",
            options: [
              %{
                name: "large",
                condition: Jido.Expr.new!(:>, [Ref.input(:value), 10]),
                action: Add,
                params: %{value: Ref.input(:value), amount: 100}
              },
              %{
                name: "positive",
                condition: Jido.Expr.new!(:>, [Ref.input(:value), 0]),
                action: Add,
                params: %{value: Ref.input(:value), amount: 10}
              }
            ],
            fallback: %{action: Add, params: %{value: Ref.input(:value), amount: -10}}
          }
        ],
        output: Ref.result("route")
      })

    rebuilt = flow |> Exec.compile!() |> Runic.Workflow.build_log() |> Runic.Workflow.from_log()
    assert %Jido.Exec.Node.Choice{} = Runic.Workflow.get_component(rebuilt, "route")

    assert Enum.any?(rebuilt.graph.vertices, fn {_id, node} ->
             match?(%Runic.Workflow.Condition{}, node)
           end)

    assert Exec.run(flow, %{value: 20}) == {:ok, %{value: 120}}
    assert Exec.run(flow, %{value: 2}) == {:ok, %{value: 12}}
    assert Exec.run(flow, %{value: 0}) == {:ok, %{value: -10}}
  end
end
