defmodule Jido.Exec.RebuildTest do
  use Covenant.Case, component: "jido_action.boundary", async: true

  alias Jido.Exec
  alias Jido.Exec.Frame
  alias Jido.Flow.Ref
  alias Jido.Action.Error.ConfigurationError
  alias JidoActionTest.Fixtures.Actions.{Add, EchoParamsAction}
  alias Runic.Workflow

  defmodule Sum do
    use Jido.Action, name: "rebuild_sum"

    @impl true
    def run(%{acc: acc, item: item}, _context), do: {:ok, %{total: acc.total + item}}
  end

  defmodule Count do
    use Jido.Action, name: "rebuild_count"

    @impl true
    def run(%{count: count}, _context), do: {:ok, %{count: count + 1}}
  end

  defmodule Child do
    use Jido.Flow, name: "rebuild_child"

    flow do
      step "add", action: Add, params: %{value: input(:value), amount: 10}
      output result("add")
    end
  end

  defmodule Decide do
    use Jido.Action, name: "rebuild_decide"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule Expand do
    use Jido.Action, name: "rebuild_expand"

    @impl true
    def run(%{value: value}, _context), do: {:continue, %{value: value}, Child}
  end

  @tag obligation: "jido_action.boundary.I5"
  test "every component kind rebuilds from its build log and returns the same result" do
    flow =
      Jido.Flow.new!(%{
        name: "rebuild_all",
        components: [
          %{
            kind: :step,
            name: "step",
            action: Add,
            params: %{value: Ref.input(:value), amount: 1}
          },
          %{
            kind: :choice,
            name: "route",
            options: [
              %{
                name: "big",
                condition: Jido.Expr.new!(:>, [Ref.input(:value), 100]),
                action: Add,
                params: %{value: Ref.input(:value), amount: 100}
              }
            ],
            fallback: %{action: Add, params: %{value: Ref.input(:value), amount: 2}}
          },
          %{
            kind: :map,
            name: "items",
            collection: Ref.input(:items),
            action: EchoParamsAction,
            params: %{item: Ref.item()}
          },
          %{
            kind: :reduce,
            name: "sum",
            collection: Ref.input(:items),
            initial: %{total: 0},
            action: Sum,
            params: %{acc: Ref.accumulator(), item: Ref.item()}
          },
          %{
            kind: :iterate,
            name: "loop",
            action: Count,
            params: %{count: Ref.state(:count)},
            state: %{initial: %{count: 0}, update: %{count: Ref.body_result(:count)}},
            completion: Jido.Expr.new!(:>=, [Ref.state(:count), 3]),
            max_iterations: 5
          },
          %{kind: :subflow, name: "child", flow: Child, params: %{value: Ref.input(:value)}}
        ],
        output: %{
          step: Ref.result("step"),
          route: Ref.result("route"),
          items: Ref.result("items"),
          sum: Ref.result("sum"),
          loop: Ref.result("loop"),
          child: Ref.result("child")
        }
      })

    input = %{value: 5, items: [1, 2, 3]}
    assert {:ok, expected} = Exec.run(flow, input)
    assert rebuilt_output(flow, input) == expected
  end

  @tag obligation: "jido_action.boundary.I5"
  test "an Invoke rebuilds and runs its dynamic Flow target" do
    flow =
      Jido.Flow.new!(%{
        name: "rebuild_dispatch",
        components: [
          %{
            kind: :invoke,
            name: "next",
            decision: Decide,
            expander: Expand,
            params: %{value: Ref.input(:value)}
          }
        ],
        output: Ref.result("next")
      })

    assert {:ok, %{value: 11} = expected} = Exec.run(flow, %{value: 1})
    assert rebuilt_output(flow, %{value: 1}) == expected
  end

  @tag obligation: "jido_action.boundary.I5"
  test "Instructions and Action nodes transmute to Runic workflows" do
    instruction = Jido.Instruction.new!(target: Add, params: %{value: 1, amount: 1})

    assert %Jido.Exec.Node.Action{} = Runic.Transmutable.to_component(instruction)
    assert %Workflow{} = Runic.Transmutable.transmute(instruction)

    node = Runic.Transmutable.to_component(instruction)
    assert ^node = Runic.Transmutable.to_component(node)
    assert %Workflow{} = Runic.Transmutable.transmute(node)

    flow_instruction = Jido.Instruction.new!(target: Child)
    assert %Workflow{} = Runic.Transmutable.to_workflow(flow_instruction)
  end

  @tag obligation: "jido_action.boundary.I5"
  test "root Action and Flow result ports rebuild from component logs" do
    action = Exec.compile!(Add)
    rebuilt_action = action |> Workflow.build_log() |> Workflow.from_log()
    assert rebuilt_action.output_ports == [result: [type: :any, from: "add_one"]]

    flow = Exec.compile!(Child)
    rebuilt_flow = flow |> Workflow.build_log() |> Workflow.from_log()
    assert [result: [type: :any, from: _name]] = rebuilt_flow.output_ports
  end

  @tag obligation: "jido_action.boundary.I5"
  test "a rebuilt Flow rejects changed Action code and keeps its Flow location" do
    target = Module.concat(__MODULE__, "Reloaded#{System.unique_integer([:positive])}")
    compile_reload_action(target, 1)

    on_exit(fn ->
      :code.purge(target)
      :code.delete(target)
    end)

    flow =
      Jido.Flow.new!(%{
        name: "rebuild_changed_target",
        components: [%{kind: :step, name: "work", action: target}],
        output: Ref.result("work")
      })

    expected_version = target.module_info(:md5)
    build_log = flow |> Exec.compile!() |> Workflow.build_log()

    :code.purge(target)
    :code.delete(target)
    compile_reload_action(target, 2)
    actual_version = target.module_info(:md5)

    rebuilt = Workflow.from_log(build_log)

    {completed, observation} =
      rebuilt
      |> Workflow.put_run_context(%{_global: %{}})
      |> Workflow.execute(Jido.Exec.Fact.local_value(Frame.new(%{})))

    assert {:error, %ConfigurationError{details: details} = error} =
             Exec.result(completed, observation)

    assert error.message == "Action target code changed after the graph was built"
    assert details.reason == :incompatible_target
    assert details.node == "work"
    assert details.node_path == ["work"]
    assert details.target == target
    assert details.expected == expected_version
    assert details.actual == actual_version
    refute details.expected == details.actual
  end

  defp rebuilt_output(flow, input) do
    rebuilt = flow |> Exec.compile!() |> Workflow.build_log() |> Workflow.from_log()

    workflow =
      rebuilt
      |> Workflow.put_run_context(%{_global: %{}})
      |> Workflow.react_until_satisfied(Workflow.Fact.new(value: Frame.new(input)),
        scheduler_policies: [{:default, %{on_failure: :halt}}]
      )

    assert [result: [type: :any, from: _name]] = workflow.output_ports
    workflow |> Workflow.results() |> Map.fetch!(:result)
  end

  defp compile_reload_action(target, version) do
    Code.compile_string("""
    defmodule #{inspect(target)} do
      use Jido.Action, name: "reloaded_action"

      @impl true
      def run(_params, _context), do: {:ok, %{version: #{version}}}
    end
    """)
  end
end
