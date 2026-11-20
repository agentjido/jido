defmodule Jido.Exec.Compile.IterateTest do
  use ExUnit.Case, async: true

  alias Jido.Error
  alias Jido.Exec
  alias Jido.Exec.Node.Iterate
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Jido.Test.Flow.Codec
  alias Runic.Workflow

  defmodule Increment do
    use Jido.Action, name: "compiled_iterate_increment"
    def run(%{count: count}, _context), do: {:ok, %{count: count + 1}, [count]}
  end

  defmodule CheckIteration do
    use Jido.Action, name: "compiled_iterate_check"

    def run(%{index: index, fail_at: index}, _context), do: {:error, :child_failed}

    def run(%{count: index, index: index, previous: previous}, _context) do
      expected = if index == 0, do: nil, else: %{count: index}

      if previous == expected,
        do: {:ok, %{count: index}, [{:checked, index}]},
        else: {:error, :wrong_previous_result}
    end
  end

  defmodule Child do
    use Jido.Flow, name: "compiled_iterate_child"

    flow do
      step "check",
        action: CheckIteration,
        params: input()

      step "increment", action: Increment, params: result("check")
      output result("increment")
    end
  end

  defmodule Parent do
    use Jido.Flow, name: "compiled_iterate_parent"

    flow do
      iterate "count" do
        state Jido.Joi.map(), initial: %{count: 0}
        flow Child
        params %{count: state(:count), index: iteration_index(), previous: body_result(), fail_at: input(:fail_at)}
        while state(:count) < input(:limit)
        max_iterations 3
      end

      output result("count")
    end
  end

  defmodule WaitBody do
    use Jido.Flow, name: "compiled_iterate_wait_body"

    flow do
      await "approval", event: "approved"
      output result("approval")
    end
  end

  defmodule SelectSuccessor do
    use Jido.Action, name: "compiled_iterate_select_successor"
    def run(_params, _context), do: {:handoff, %{count: 0}, Increment}
  end

  defmodule HandoffBody do
    use Jido.Flow, name: "compiled_iterate_handoff_body"

    flow do
      handoff "next", selector: SelectSuccessor, params: %{}
      output result("next")
    end
  end

  test "DSL and map Flow bodies use the same call and survive a Catalog round trip" do
    assert %{kind: :flow, target: Child} = call = Parent.flow().components["count"].call
    assert Flow.new!(parent_attrs()).components["count"].call == call

    assert {:ok, document, catalog} = Codec.encode(Parent.flow())
    assert [stored] = document["components"]
    assert stored["call"]["kind"] == "flow"
    assert {:ok, restored} = Codec.decode(document, catalog)
    assert restored.components["count"].call == call
    assert Exec.run(restored, %{limit: 3, fail_at: nil}) == child_result(3)
  end

  test "map Iterate requires a single target field and preparation checks its kind" do
    %{components: [component]} = attrs = parent_attrs()
    without_target = Map.delete(component, :flow)

    for invalid <- [without_target, Map.put(component, :action, Increment)] do
      assert {:error, error} = Flow.new(%{attrs | components: [invalid]})
      assert Exception.message(error) =~ "iterate requires exactly one of action or flow"
    end

    for {field, target, actual} <- [{:flow, Increment, :action}, {:action, Child, :flow}] do
      invalid =
        without_target
        |> Map.put(field, target)
        |> put_in([:state, :update], Ref.body_result())

      flow = Flow.new!(%{attrs | components: [invalid]})

      assert {:error, %{details: %{field: ^field, expected: ^field, actual: ^actual}}} =
               Exec.compile(flow, [])
    end
  end

  test "a Flow body receives current state, iteration index and previous output in a rebuilt workflow" do
    assert {:ok, workflow} = Exec.compile(Parent, [])
    assert %Iterate{child_workflow: %Workflow{}} = Workflow.get_component(workflow, "count")
    rebuilt = workflow |> Workflow.build_log() |> Workflow.from_log()
    {rebuilt, observation} = Workflow.execute(rebuilt, %{limit: 3, fail_at: nil})

    assert Exec.result(rebuilt, observation) == child_result(3)
  end

  test "a child failure retains the second iteration position and child path" do
    assert {:error, error} = Exec.run(Parent, %{limit: 3, fail_at: 1})
    assert %{iteration_index: 1, state_revision: 1, node_path: ["count", "check"]} = error.details
  end

  test "a Flow body can complete with zero calls and observes the iteration limit" do
    assert {:ok, %{iterations: 0, state: %{count: 0}, output: nil}} =
             Exec.run(Parent, %{limit: 0})

    assert {:error, %{phase: :iterate_exhaustion, details: %{completed_iterations: 3, state_revision: 3}}} =
             Exec.run(Parent, %{limit: 4, fail_at: 3})
  end

  test "a Flow body rejects nested waits and handoffs" do
    %{components: [component]} = attrs = parent_attrs()

    for {target, reason} <- [{WaitBody, :nested_wait}, {HandoffBody, :nested_handoff}] do
      flow = Flow.new!(%{attrs | components: [%{component | flow: target}]})
      assert {:error, %{details: %{reason: ^reason}}} = Exec.run(flow, %{limit: 1, fail_at: nil})
    end
  end

  defp parent_attrs do
    %{
      name: "compiled_iterate_data_parent",
      components: [
        %{
          kind: :iterate,
          name: "count",
          flow: Child,
          params: %{
            count: Ref.state(:count),
            index: Ref.iteration_index(),
            previous: Ref.body_result(),
            fail_at: Ref.input(:fail_at)
          },
          state: %{initial: %{count: 0}},
          completion: Jido.Expr.new!(:>=, [Ref.state(:count), Ref.input(:limit)]),
          max_iterations: 3
        }
      ],
      output: Ref.result("count")
    }
  end

  defp child_result(count) do
    {:ok, %{kind: :jido_flow_iterate_result, iterations: count, state: %{count: count}, output: %{count: count}},
     Enum.flat_map(0..(count - 1), &[{:checked, &1}, &1])}
  end

  test "compile lowers one Iterate to one dedicated Runic Iterate component" do
    assert {:ok, %Workflow{} = workflow} = Exec.compile(iterate_flow("compiled_iterate_shape", 3), [])

    assert %Iterate{name: "count", definition: %{kind: :iterate}} =
             iterate = Workflow.get_component(workflow, "count")

    assert [bindings: input_opts] = Runic.Component.inputs(iterate)
    assert input_opts[:type] == :any
    assert Keyword.keys(Runic.Component.outputs(iterate)) == [:value, :effects, :control]
  end

  test "Iterate replaces state until its completion expression is true" do
    assert Exec.run(iterate_flow("compiled_iterate_execution", 3)) ==
             {:ok,
              %{
                kind: :jido_flow_iterate_result,
                iterations: 3,
                state: %{count: 3},
                output: %{count: 3}
              }, [0, 1, 2]}
  end

  test "Iterate can complete before it runs its Action" do
    assert Exec.run(iterate_flow("compiled_iterate_zero", 0)) ==
             {:ok,
              %{
                kind: :jido_flow_iterate_result,
                iterations: 0,
                state: %{count: 0},
                output: nil
              }}
  end

  test "Iterate reports maximum iteration exhaustion" do
    flow = iterate_flow("compiled_iterate_exhaustion", 3, 2)

    assert {:error, %Error.ExecutionError{} = error} = Exec.run(flow)
    assert error.phase == :iterate_exhaustion
    assert error.details.completed_iterations == 2
  end

  test "a rebuilt Iterate keeps state replacement and effect order" do
    assert {:ok, workflow} = Exec.compile(iterate_flow("compiled_iterate_rebuild", 2), [])
    rebuilt = workflow |> Workflow.build_log() |> Workflow.from_log()
    {rebuilt, observation} = Workflow.execute(rebuilt, %{})

    assert Exec.result(rebuilt, observation) ==
             {:ok,
              %{
                kind: :jido_flow_iterate_result,
                iterations: 2,
                state: %{count: 2},
                output: %{count: 2}
              }, [0, 1]}
  end

  defp iterate_flow(name, limit, max_iterations \\ 5) do
    Flow.new!(%{
      name: name,
      components: [
        %{
          kind: :iterate,
          name: "count",
          action: Increment,
          params: %{count: Ref.state(:count)},
          state: %{initial: %{count: 0}, update: %{count: Ref.body_result(:count)}},
          completion: Jido.Expr.new!(:>=, [Ref.state(:count), limit]),
          max_iterations: max_iterations
        }
      ],
      output: Ref.result("count")
    })
  end
end
