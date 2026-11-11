defmodule Jido.Exec.Compile.ChoiceTest do
  use ExUnit.Case, async: true

  @moduletag obligation: "jido_action.execution.I17"

  alias Jido.Error
  alias Jido.Exec
  alias Jido.Exec.Node.Choice
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Jido.Test.Action.Fixtures.Actions.{EchoParamsAction, ErrorAction, ExtrasAction}
  alias Runic.Workflow

  test "compile lowers one Choice to one dedicated Runic Choice component" do
    flow = choice_flow("compiled_choice_shape", [option("yes", true, %{selected: :option})], %{selected: :fallback})

    assert {:ok, %Workflow{} = workflow} = Exec.compile(flow, [])

    assert %Choice{name: "route", definition: %{kind: :choice}} =
             choice = Workflow.get_component(workflow, "route")

    assert [bindings: input_opts] = Runic.Component.inputs(choice)
    assert input_opts[:type] == :any
    assert Keyword.keys(Runic.Component.outputs(choice)) == [:value, :effects, :control]
    assert component_sources(workflow, "route") == ["__jido_input__/compiled_choice_shape"]

    output =
      workflow
      |> Workflow.components()
      |> Map.values()
      |> Enum.find(&is_struct(&1, Jido.Exec.Node.Output))

    assert Enum.sort(component_sources(workflow, output.name)) ==
             ["__jido_input__/compiled_choice_shape", "route"]
  end

  test "Choice runs only the first matching option" do
    flow =
      choice_flow(
        "compiled_choice_order",
        [option("first", true, %{selected: :first}), option("second", true, %{selected: :second})],
        %{selected: :fallback}
      )

    assert compile_and_execute(flow, %{}) == {:ok, %{selected: :first}}
  end

  test "Choice runs its fallback when no option matches" do
    flow =
      choice_flow(
        "compiled_choice_fallback",
        [option("no", false, %{selected: :option})],
        %{selected: :fallback}
      )

    assert compile_and_execute(flow, %{}) == {:ok, %{selected: :fallback}}
  end

  test "an option named fallback is distinct from the Choice fallback" do
    flow =
      choice_flow(
        "compiled_choice_named_fallback",
        [option("fallback", true, %{selected: :named_option})],
        %{selected: :fallback}
      )

    assert compile_and_execute(flow, %{}) == {:ok, %{selected: :named_option}}
  end

  test "Choice does not resolve parameters for an unselected call" do
    flow =
      choice_flow(
        "compiled_choice_lazy_params",
        [option("yes", true, %{selected: :option})],
        %{selected: Ref.input(:missing)}
      )

    assert compile_and_execute(flow, %{}) == {:ok, %{selected: :option}}
  end

  test "a selected Action failure does not run the Choice fallback" do
    flow =
      choice_flow(
        "compiled_choice_selected_failure",
        [option("fail", true, %{error_type: :runtime}, ErrorAction)],
        %{selected: :fallback}
      )

    assert {:error, %Error.ExecutionError{} = error} = compile_and_execute(flow, %{})
    assert error.message == "Runtime error"
    assert error.details.node == "route"
    assert error.details.node_path == ["route"]
  end

  test "a Choice condition error keeps the Choice source path" do
    flow =
      choice_flow(
        "compiled_choice_condition_error",
        [option("missing", Ref.input(:missing), %{selected: :option})],
        %{selected: :fallback}
      )

    assert {:error, %Error.ExecutionError{} = error} = compile_and_execute(flow, %{})
    assert error.details.reason == :missing_key
    assert error.details.node == "route"
    assert error.details.node_path == ["route"]
  end

  test "Choice preserves effects from the selected Action" do
    flow =
      choice_flow(
        "compiled_choice_effects",
        [option("yes", true, %{value: 8}, ExtrasAction)],
        %{selected: :fallback}
      )

    assert {:ok, workflow} = Exec.compile(flow, [])

    {workflow, observation} =
      workflow
      |> Workflow.put_run_context(%{_global: %{trace_id: "choice-8"}})
      |> Workflow.execute(%{})

    assert Exec.result(workflow, observation) ==
             {:ok, %{value: 8}, [%{trace_id: "choice-8"}]}
  end

  test "a rebuilt Choice keeps its ordered selection" do
    flow =
      choice_flow(
        "compiled_choice_rebuild",
        [option("first", true, %{selected: :first}), option("second", true, %{selected: :second})],
        %{selected: :fallback}
      )

    assert {:ok, workflow} = Exec.compile(flow, [])
    rebuilt = workflow |> Workflow.build_log() |> Workflow.from_log()

    assert execute(rebuilt, %{}) == {:ok, %{selected: :first}}
  end

  defp choice_flow(name, options, fallback_params) do
    Flow.new!(%{
      name: name,
      components: [
        %{
          kind: :choice,
          name: "route",
          options: options,
          fallback: %{action: EchoParamsAction, params: fallback_params}
        }
      ],
      output: Ref.result("route")
    })
  end

  defp option(name, condition, params, action \\ EchoParamsAction) do
    %{name: name, condition: condition, action: action, params: params}
  end

  defp compile_and_execute(flow, input) do
    assert {:ok, workflow} = Exec.compile(flow, [])
    execute(workflow, input)
  end

  defp execute(workflow, input) do
    {workflow, observation} = Workflow.execute(workflow, input)
    Exec.result(workflow, observation)
  end

  defp component_sources(workflow, name) do
    graph = Workflow.component_graph(workflow)
    component = Workflow.get_component!(workflow, name)

    graph
    |> Multigraph.in_neighbors(component)
    |> Enum.map(& &1.name)
  end
end
