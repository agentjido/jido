defmodule Jido.Exec.CompilerTest do
  use ExUnit.Case, async: true

  alias Jido.Exec
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Jido.Test.Action.Fixtures.Actions.EchoParamsAction
  alias Runic.Workflow

  defmodule CountedLeaf do
    @behaviour Jido.Flow

    @impl true
    def flow do
      send(self(), {:materialized, __MODULE__})

      Jido.Flow.new!(%{
        name: "counted_leaf",
        components: [
          %{kind: :step, name: "pass", action: EchoParamsAction, params: %{value: 1}}
        ],
        output: Ref.result("pass")
      })
    end

    @impl true
    def validate_params(params), do: {:ok, params}

    @impl true
    def validate_output(output), do: {:ok, output}
  end

  defmodule CountedChild do
    @behaviour Jido.Flow

    @impl true
    def flow do
      send(self(), {:materialized, __MODULE__})

      Jido.Flow.new!(%{
        name: "counted_child",
        components: [%{kind: :subflow, name: "leaf", flow: CountedLeaf, params: %{}}],
        output: Ref.result("leaf")
      })
    end

    @impl true
    def validate_params(params), do: {:ok, params}

    @impl true
    def validate_output(output), do: {:ok, output}
  end

  defmodule RecursiveChild do
    @behaviour Jido.Flow

    @impl true
    def flow do
      Flow.new!(%{
        name: "recursive_child",
        components: [%{kind: :subflow, name: "child", flow: __MODULE__}],
        output: Ref.result("child")
      })
    end

    @impl true
    def validate_params(params), do: {:ok, params}

    @impl true
    def validate_output(output), do: {:ok, output}
  end

  defmodule OutputProbe do
    use Jido.Action,
      name: "compiler_output_probe",
      output_schema: Jido.Joi.object(%{id: Jido.Joi.integer()}, unrecognized_keys: :error)

    def run(%{test_pid: pid}, _context) do
      send(pid, :action_ran)
      {:ok, %{id: 1}}
    end
  end

  test "preparation rejects a scalar literal output before an Action runs" do
    flow = flow!("invalid_output", [%{kind: :step, name: "load", action: OutputProbe, params: Ref.input([])}], 42)
    source = %{file: "source.ex", line: 20}

    assert {:error, %{details: %{path: [:output], file: "source.ex", line: 20}}} =
             Exec.compile(flow, source_map: %{[:output] => source})

    assert {:error, %{details: %{path: [:output]}}} = Exec.run(flow, %{test_pid: self()})
    assert {:error, %{details: %{path: [:output]}}} = Exec.run(%{flow | output: [42]}, %{test_pid: self()})
    refute_received :action_ran
  end

  test "inspection reports known host requirements and closed result fields" do
    load = %{kind: :step, name: "load", action: OutputProbe}
    closed = flow!("closed_output", [load], %{id: Ref.result("load", :id_typo)})

    assert {:ok, %{requirements: [], advisories: [advisory]}} = Flow.explain(closed)
    assert %{code: :unknown_result_field, component: "load", path: [:id_typo]} = advisory
    assert {:ok, %Workflow{}} = Exec.compile(closed, [])

    open = flow!("open_output", [%{load | action: EchoParamsAction}], closed.output)
    assert {:ok, %{requirements: [], advisories: []}} = Flow.explain(open)

    wait = flow!("with_timer", [%{kind: :timer, name: "timer", after_ms: 1}], Ref.result("timer"))
    assert {:ok, %{requirements: [:waits], advisories: []}} = Flow.explain(wait)
  end

  test "one compile materializes each shared child module once at every nesting depth" do
    flow =
      flow!(
        "shared_children",
        [
          %{kind: :subflow, name: "left", flow: CountedChild, params: %{}},
          %{kind: :subflow, name: "right", flow: CountedChild, params: %{}}
        ],
        Ref.result("right")
      )

    for _operation <- 1..2 do
      assert {:ok, %Workflow{}} = Exec.compile(flow, [])
      assert_received {:materialized, CountedChild}
      assert_received {:materialized, CountedLeaf}
      refute_received {:materialized, _module}
    end
  end

  test "root and child Flow definitions share one compile operation" do
    assert {:ok, %Workflow{}} = Exec.compile(CountedChild, [])
    assert_received {:materialized, CountedChild}
    assert_received {:materialized, CountedLeaf}
    refute_received {:materialized, _module}
  end

  test "definition reuse preserves recursive child rejection" do
    assert {:error, error} = Exec.compile(RecursiveChild, [])
    assert error.message == "recursive nested Flow cycle"
    assert error.details.module_stack == [RecursiveChild, RecursiveChild]
  end

  defp flow!(name, components, output) do
    Flow.new!(%{name: name, components: components, output: output})
  end
end
