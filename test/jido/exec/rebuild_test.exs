defmodule Jido.Exec.RebuildTest do
  use Covenant.Case, component: "jido_action.boundary", async: true

  alias Jido.Exec
  alias Jido.Flow.Ref
  alias Jido.Error.ValidationError
  alias Jido.Test.Action.Fixtures.Actions.{Add, EchoParamsAction}
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
  test "root Action and Flow result ports rebuild from component logs" do
    action = Jido.Exec.Compiler.compile!(Add)
    rebuilt_action = action |> Workflow.build_log() |> Workflow.from_log()
    assert [result: [type: :any, from: _name]] = rebuilt_action.output_ports

    flow = Jido.Exec.Compiler.compile!(Child)
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
    build_log = flow |> Jido.Exec.Compiler.compile!() |> Workflow.build_log()

    :code.purge(target)
    :code.delete(target)
    compile_reload_action(target, 2)
    actual_version = target.module_info(:md5)

    rebuilt = Workflow.from_log(build_log)

    {completed, observation} =
      rebuilt
      |> Workflow.put_run_context(%{_global: %{}})
      |> Workflow.execute(%{})

    assert {:error, %ValidationError{details: details} = error} =
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

  @tag obligation: "jido_action.boundary.I5"
  test "a rebuilt parent Flow rejects changed child Flow code" do
    target = Module.concat(__MODULE__, "ReloadedFlow#{System.unique_integer([:positive])}")
    compile_reload_flow(target, 1)

    on_exit(fn ->
      :code.purge(target)
      :code.delete(target)
    end)

    parent =
      Jido.Flow.new!(%{
        name: "rebuild_changed_child_flow",
        components: [%{kind: :subflow, name: "child", flow: target, params: %{}}],
        output: Ref.result("child")
      })

    expected_version = target.module_info(:md5)
    build_log = parent |> Jido.Exec.Compiler.compile!() |> Workflow.build_log()

    :code.purge(target)
    :code.delete(target)
    compile_reload_flow(target, 2)
    actual_version = target.module_info(:md5)

    {completed, observation} =
      build_log
      |> Workflow.from_log()
      |> Workflow.put_run_context(%{_global: %{}})
      |> Workflow.execute(%{})

    assert {:error, %ValidationError{details: details} = error} =
             Exec.result(completed, observation)

    assert error.message == "Flow target code changed after the graph was built"
    assert details.reason == :incompatible_target
    assert details.node == "child"
    assert details.target == target
    assert details.expected == expected_version
    assert details.actual == actual_version
  end

  defp rebuilt_output(flow, input) do
    rebuilt = flow |> Jido.Exec.Compiler.compile!() |> Workflow.build_log() |> Workflow.from_log()

    workflow =
      rebuilt
      |> Workflow.put_run_context(%{_global: %{}})
      |> Workflow.react_until_satisfied(Workflow.Fact.new(value: input),
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

  defp compile_reload_flow(target, version) do
    Code.compile_string("""
    defmodule #{inspect(target)} do
      @behaviour Jido.Flow

      @impl true
      def flow do
        Jido.Flow.new!(%{
          name: "reloaded_flow",
          components: [
            %{
              kind: :step,
              name: "version",
              action: Jido.Test.Action.Fixtures.Actions.Add,
              params: %{value: #{version}, amount: 0}
            }
          ],
          output: %{version: Jido.Flow.Ref.result("version", :value)}
        })
      end

      @impl true
      def validate_params(params), do: {:ok, params}

      @impl true
      def validate_output(output), do: {:ok, output}
    end
    """)
  end
end
