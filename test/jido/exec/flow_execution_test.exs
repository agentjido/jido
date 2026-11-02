defmodule Jido.Exec.FlowExecutionTest do
  use Covenant.Case, component: "jido_action.boundary", async: true

  alias Jido.Exec
  alias Jido.Flow
  alias Jido.Flow.Ref

  alias JidoActionTest.Fixtures.Actions.{
    Add,
    ContextEcho,
    ErrorAction,
    FullAction,
    Multiply
  }

  defmodule EffectAction do
    use Jido.Action, name: "exec_v2_effect"

    @impl true
    def run(%{label: label, value: value}, _context), do: {:ok, %{value: value}, [label]}
  end

  @tag obligation: "jido_action.boundary.I5"
  test "independent branches join through Runic readiness" do
    flow =
      flow!(
        "branch_join",
        [
          step("left", Add, %{value: Ref.input(:value), amount: 1}),
          step("right", Multiply, %{value: Ref.input(:value), amount: 2}),
          step("join", FullAction, %{
            a: Ref.result("left", :value),
            b: Ref.result("right", :value)
          })
        ],
        Ref.result("join")
      )

    assert Exec.run(flow, %{value: 3}) == {:ok, %{a: 4, b: 6, result: 10}}
  end

  @tag obligation: "jido_action.boundary.I5"
  test "Flow parameters read input, prior results, and runtime context" do
    flow =
      flow!(
        "context",
        [step("echo", ContextEcho, %{value: Ref.input(:value)})],
        Ref.result("echo")
      )

    assert Exec.run(flow, %{value: 7}, %{trace_id: "trace-7"}) ==
             {:ok, %{value: 7, trace_id: "trace-7"}}
  end

  @tag obligation: "jido_action.boundary.I4"
  test "deferred effects use canonical component order after a branch join" do
    flow =
      flow!(
        "effects",
        [
          step("b", EffectAction, %{label: :b, value: Ref.input(:value)}),
          step("a", EffectAction, %{label: :a, value: Ref.input(:value)})
        ],
        %{a: Ref.result("a", :value), b: Ref.result("b", :value)}
      )

    assert Exec.run(flow, %{value: 5}) == {:ok, %{a: 5, b: 5}, [:a, :b]}
  end

  defmodule TwoParentChild do
    use Jido.Flow, name: "two_parent_child"

    flow do
      step "sum", action: FullAction, params: %{a: input(:a), b: input(:b)}
      output result("sum")
    end
  end

  @tag obligation: "jido_action.boundary.I5"
  test "a nested Flow waits for every parent dependency" do
    parent =
      flow!(
        "two_parent_parent",
        [
          step("left", Add, %{value: Ref.input(:value), amount: 1}),
          step("right", Multiply, %{value: Ref.input(:value), amount: 2}),
          %{
            kind: :subflow,
            name: "child",
            flow: TwoParentChild,
            params: %{a: Ref.result("left", :value), b: Ref.result("right", :value)}
          }
        ],
        Ref.result("child")
      )

    for max_concurrency <- [1, 3] do
      assert Exec.run(parent, %{value: 3}, %{}, max_concurrency: max_concurrency) ==
               {:ok, %{a: 4, b: 6, result: 10}}
    end
  end

  defmodule ListOutputFlow do
    use Jido.Flow, name: "list_output_module"

    flow do
      step "add", action: Add, params: %{value: input(:value), amount: 1}
      output [result("add")]
    end
  end

  defmodule RawAction do
    use Jido.Action, name: "flow_raw_output"

    @impl true
    def run(_params, _context), do: {:ok, Jido.Action.Output.raw("done")}
  end

  @tag obligation: "jido_action.boundary.I3"
  test "data and module Flows apply the same map output rule" do
    add = step("add", Add, %{value: Ref.input(:value), amount: 1})
    data = flow!("list_output", [add], [Ref.result("add")])

    for target <- [data, ListOutputFlow] do
      assert {:error, %Jido.Action.Error.InvalidInputError{} = error} =
               Exec.run(target, %{value: 1})

      assert error.details.phase == :flow_output
    end

    raw = flow!("raw_output", [step("raw", RawAction, %{})], Ref.result("raw"))
    assert {:ok, %Jido.Action.Output{kind: :raw, value: "done"}} = Exec.run(raw)
  end

  defmodule NestedControlChild do
    use Jido.Flow, name: "nested_control_child"

    flow do
      map "items", collection: input(:items), action: ErrorAction, params: %{error_type: item()}

      choice "route" do
        option "fail" do
          condition(input(:route) == "fail")
          action(ErrorAction)
          params(%{error_type: :runtime})
        end

        otherwise action: Add, params: %{value: 1, amount: 1}
      end

      output %{items: result("items"), route: result("route")}
    end
  end

  @tag obligation: "jido_action.boundary.I2"
  test "control component failures in a nested Flow keep the parent path" do
    for {input, node} <- [
          {%{items: [:runtime], route: "pass"}, "items"},
          {%{items: [], route: "fail"}, "route"}
        ] do
      parent =
        flow!(
          "nested_control_parent",
          [
            %{
              kind: :subflow,
              name: "child",
              flow: NestedControlChild,
              params: %{items: Ref.input(:items), route: Ref.input(:route)}
            }
          ],
          Ref.result("child")
        )

      assert {:error, error} = Exec.run(parent, input)
      assert error.details.node_path == ["child", node]
    end
  end

  @tag obligation: "jido_action.boundary.I2"
  test "an Action failure stops dependent Flow work" do
    flow =
      flow!(
        "failure",
        [
          step("fail", ErrorAction, %{error_type: :validation}),
          step("blocked", Add, %{value: Ref.result("fail", :value), amount: 1})
        ],
        Ref.result("blocked")
      )

    assert {:error, %Jido.Action.Error.ExecutionFailureError{message: "Validation error"}} =
             Exec.run(flow)
  end

  defp flow!(name, components, output) do
    Flow.new!(%{name: name, components: components, output: output})
  end

  defp step(name, action, params) do
    %{kind: :step, name: name, action: action, params: params}
  end
end
