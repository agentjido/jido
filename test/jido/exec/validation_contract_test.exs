defmodule Jido.Exec.ValidationContractTest do
  use Covenant.Case, component: "jido_action.boundary", async: true

  alias Jido.Action.{Error, Output}
  alias Jido.Exec
  alias Jido.Exec.Validation
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Runic.Workflow.SingleOutput.{Context, Result}

  @moduletag capture_log: true

  defmodule PassThrough do
    use Jido.Action, name: "validation_pass_through"
    def run(value, _context), do: {:ok, value}
  end

  defmodule ActionValidator do
    @behaviour Jido.Action
    def validate_params(value), do: Jido.Exec.ValidationContractTest.validate(value, :input)
    def validate_output(value), do: Jido.Exec.ValidationContractTest.validate(value, :output)
    def run(value, _context), do: {:ok, value}
  end

  defmodule FlowValidator do
    @behaviour Jido.Flow
    def flow do
      Flow.new!(%{
        name: "validator_contract",
        components: [%{kind: :step, name: "pass", action: PassThrough, params: Ref.input([])}],
        output: Ref.result("pass")
      })
    end

    def validate_params(value), do: Jido.Exec.ValidationContractTest.validate(value, :input)
    def validate_output(value), do: Jido.Exec.ValidationContractTest.validate(value, :output)
    def __jido_flow_source_map__, do: %{[:output] => %{file: "validator_output.ex", line: 7}}
  end

  defmodule ParentAction do
    use Jido.Flow, name: "parent_action_validator"

    flow do
      step "child", action: ActionValidator, params: input([])
      output result("child")
    end
  end

  defmodule ParentFlow do
    use Jido.Flow, name: "parent_flow_validator"

    flow do
      step "child", action: FlowValidator, params: input([])
      output result("child")
    end
  end

  defmodule PreparedAction do
    use Jido.Action,
      name: "prepared_validation_contract",
      schema:
        Zoi.object(%{value: Zoi.integer()}, unrecognized_keys: :preserve)
        |> Zoi.transform({Jido.Exec.ValidationContractTest, :transform, [:input]}),
      output_schema:
        Zoi.object(%{value: Zoi.integer()}, unrecognized_keys: :preserve)
        |> Zoi.transform({Jido.Exec.ValidationContractTest, :transform, [:output]})

    def on_before_validate_params(%{test_pid: pid} = value) do
      send(pid, :prepared)
      {:ok, Map.update!(value, :value, &String.to_integer/1)}
    end

    def run(value, _context), do: {:ok, value}
  end

  def validate(%{phase: phase, failure: failure}, phase), do: fail(failure)

  def validate(%{test_pid: pid} = value, phase) do
    send(pid, {:validated, phase})
    {:ok, Map.update!(value, :value, &(&1 + 1))}
  end

  def validate(value, _phase), do: {:ok, value}

  def fail(:raise), do: raise("validator failure")
  def fail(:throw), do: throw(:validator_failure)
  def fail(:exit), do: exit(:validator_failure)
  def fail(:invalid), do: :invalid
  def fail(:reason), do: {:error, :rejected}
  def fail(:exception), do: {:error, Error.validation_error("rejected", %{original: true})}
  def fail(:scalar_success), do: {:ok, 42}
  def fail(:invalid_envelope), do: {:ok, %Output{kind: :stream, value: 42, meta: %{}}}

  def scalar(_value, _opts), do: 42

  def transform(%{test_pid: pid} = value, phase, _opts) do
    send(pid, {:transformed, phase})
    Map.update!(value, :value, &(&1 + 1))
  end

  @tag obligation: [
         "jido_action.boundary.I1",
         "jido_action.boundary.I2",
         "jido_action.boundary.I3"
       ]
  test "Action and Flow validators protect each execution boundary" do
    for target <- [ActionValidator, FlowValidator], phase <- [:input, :output] do
      for {executable, expected_phase, node_path} <- boundaries(target, phase),
          failure <- [:raise, :throw, :exit, :invalid, :reason, :exception] do
        assert {:error, error} = Exec.run(executable, %{phase: phase, failure: failure})
        assert Map.get(error.details, :phase, expected_phase) == expected_phase

        if node_path do
          if component_location?(target, phase) do
            assert error.details.node_path == node_path

            assert error.details.source ==
                     executable.__jido_flow_source_map__()[[:components, "child"]]
          else
            assert error.details.source == FlowValidator.__jido_flow_source_map__()[[:output]]
          end
        end

        case failure do
          :invalid ->
            assert %Error.InternalError{} = error
            assert error.details.reason == :invalid_validator_return
            assert error.details.return == :invalid

          :reason ->
            assert %Error.InvalidInputError{} = error
            assert error.details.reason == :rejected

          :exception ->
            assert %Error.InvalidInputError{} = error
            assert error.details.original

          failure ->
            assert %Error.ExecutionFailureError{} = error
            assert %Splode.Stacktrace{} = error.stacktrace
            assert error.stacktrace.stacktrace == error.details.stacktrace

            assert Enum.any?(error.details.stacktrace, fn
                     {__MODULE__, :fail, 1, _location} -> true
                     _frame -> false
                   end)

            if failure == :raise do
              assert error.details.exception == RuntimeError
              assert error.message == "validator failure"
            else
              assert error.details.kind == failure
              assert error.details.reason == :validator_failure
            end
        end
      end
    end
  end

  @tag obligation: ["jido_action.boundary.I1", "jido_action.boundary.I3"]
  test "custom validators reject scalar success at root and nested boundaries" do
    for target <- [ActionValidator, FlowValidator],
        phase <- [:input, :output],
        {executable, expected_phase, _node_path} <- boundaries(target, phase) do
      assert {:error, %Error.InternalError{} = error} =
               Exec.run(executable, %{phase: phase, failure: :scalar_success})

      assert error.message == "Action validator returned an invalid value"
      assert error.details.action == target
      assert error.details.phase == expected_phase
      assert error.details.return == {:ok, 42}
      assert error.details.reason == :invalid_validator_return
    end
  end

  @tag obligation: ["jido_action.boundary.I3", "jido_action.boundary.I4"]
  test "custom output validators reject malformed envelopes at root and nested boundaries" do
    invalid = %Output{kind: :stream, value: 42, meta: %{}}

    for target <- [ActionValidator, FlowValidator],
        {executable, _expected_phase, _node_path} <- boundaries(target, :output) do
      assert {:error, %Error.InvalidInputError{} = error} =
               Exec.run(executable, %{phase: :output, failure: :invalid_envelope})

      assert error.message == "invalid action output envelope"
      assert error.details.value == invalid
    end
  end

  @tag obligation: "jido_action.boundary.I1"
  test "absent validation targets preserve input and output values" do
    for value <- [%{value: 1}, Output.raw(42)] do
      assert {:ok, ^value} = Validation.input(nil, value)
      assert {:ok, ^value} = Validation.output(nil, value)
    end
  end

  @tag obligation: ["jido_action.boundary.I1", "jido_action.boundary.I3"]
  test "schema validation retains context when a transformation returns a scalar" do
    details = %{module: Jido.Flow, flow: "scalar", context: "Flow output"}

    assert {:error, %Error.InvalidInputError{} = error} =
             Validation.schema(scalar_schema(), %{}, details)

    assert error.message == "Flow output validation must return a map"
    assert error.details == Map.put(details, :value, 42)
  end

  @tag obligation: "jido_action.boundary.I1"
  test "root and nested data Flow input schemas reject scalar transformations" do
    flow = data_flow(%{name: "scalar_input", schema: scalar_schema(), output: %{}})

    for run <- data_boundaries(flow) do
      assert {:error, %Error.InvalidInputError{} = error} = run.(%{})
      assert error.message == "Flow input must be a map"
      assert error.details.flow == "scalar_input"
      assert error.details.module == Jido.Flow
      assert error.details.context == "Flow"
      assert error.details.value == 42
      assert error.details.phase in [:flow_input, :subflow_input]
    end
  end

  @tag obligation: ["jido_action.boundary.I1", "jido_action.boundary.I10"]
  test "managed Flow input failures preserve the validator error" do
    runner = :"validation_contract_runner_#{System.unique_integer([:positive])}"
    start_supervised!({Runic.Runner, name: runner})

    for failure <- [:raise, :throw, :exit, :invalid, :reason, :exception] do
      assert {:error, error} =
               Exec.start(runner, make_ref(), FlowValidator, %{phase: :input, failure: failure})

      assert error.details.phase == :flow_input
      refute Map.has_key?(error.details, :non_portable_durable_value)
    end
  end

  @tag obligation: "jido_action.boundary.I3"
  test "root and nested data Flow output schemas reject scalar transformations" do
    flow = data_flow(%{name: "scalar_output", output_schema: scalar_schema(), output: %{}})

    for run <- data_boundaries(flow) do
      assert {:error, %Error.InvalidInputError{} = error} = run.(%{})
      assert error.message == "Action output validation must return a map"
      assert error.details.flow == "scalar_output"
      assert error.details.module == Jido.Flow
      assert error.details.context == "Flow output"
      assert error.details.value == 42
      assert Map.get(error.details, :phase, :subflow_output) in [:flow_output, :subflow_output]
    end
  end

  @tag obligation: ["jido_action.boundary.I1", "jido_action.boundary.I3"]
  test "module validators run once and retain each transformation" do
    for target <- [ActionValidator, FlowValidator, ParentAction, ParentFlow] do
      assert {:ok, %{value: 2}} = Exec.run(target, %{test_pid: self(), value: 0})
      assert_received {:validated, :input}
      assert_received {:validated, :output}
      refute_received {:validated, _phase}
    end
  end

  @tag obligation: ["jido_action.boundary.I1", "jido_action.boundary.I3"]
  test "preparation and Action schemas run once with explicit key preservation" do
    assert {:ok, %{value: 3, extra: :kept}} =
             Exec.run(PreparedAction, %{test_pid: self(), value: "1", extra: :kept})

    assert_received :prepared
    assert_received {:transformed, :input}
    assert_received {:transformed, :output}
    refute_received :prepared
    refute_received {:transformed, _phase}
  end

  @tag obligation: ["jido_action.boundary.I1", "jido_action.boundary.I3"]
  test "data Flow schemas run once at root and nested boundaries" do
    flow =
      data_flow(%{
        name: "transformed_data",
        schema: transform_schema(:input),
        output_schema: transform_schema(:output),
        output: Ref.input([])
      })

    for run <- data_boundaries(flow) do
      assert {:ok, %{value: 2, extra: :kept}} =
               run.(%{test_pid: self(), value: 0, extra: :kept})

      assert_received {:transformed, :input}
      assert_received {:transformed, :output}
      refute_received {:transformed, _phase}
    end
  end

  @tag obligation: ["jido_action.boundary.I3", "jido_action.boundary.I4"]
  test "data Flow output validates envelopes without running the output schema" do
    flow =
      data_flow(%{
        name: "envelope_data",
        output_schema: transform_schema(:output),
        output: Ref.input(:output)
      })

    for run <- data_boundaries(flow) do
      output = Output.raw(42)
      assert {:ok, ^output} = run.(%{output: output})

      invalid = %{output | kind: :invalid}

      assert {:error, %Error.InvalidInputError{message: "invalid action output envelope"}} =
               run.(%{output: invalid})
    end

    refute_received {:transformed, _phase}
  end

  defp scalar_schema, do: Zoi.any() |> Zoi.transform({__MODULE__, :scalar, []})

  def data_flow(attrs) do
    Map.merge(
      %{
        components: [%{kind: :step, name: "pass", action: PassThrough, params: Ref.input([])}],
        output: Ref.result("pass")
      },
      attrs
    )
    |> Flow.new!()
  end

  defp transform_schema(phase),
    do:
      Zoi.object(%{value: Zoi.integer()}, unrecognized_keys: :preserve)
      |> Zoi.transform({__MODULE__, :transform, [phase]})

  defp boundaries(ActionValidator, phase) do
    [{ActionValidator, phase, nil}, {ParentAction, phase, ["child"]}]
  end

  defp boundaries(FlowValidator, phase) do
    root_phase = if phase == :input, do: :flow_input, else: :flow_output
    nested_phase = if phase == :input, do: :subflow_input, else: :subflow_output
    [{FlowValidator, root_phase, nil}, {ParentFlow, nested_phase, ["child"]}]
  end

  defp component_location?(ActionValidator, _phase), do: true
  defp component_location?(_target, :input), do: true
  defp component_location?(_target, :output), do: false

  defp data_boundaries(flow), do: [&Exec.run(flow, &1), &resolve_nested(flow, &1)]

  defp resolve_nested(flow, params) do
    input =
      Jido.Exec.Node.Input.new(
        id: :input,
        name: "child_input",
        component: "child",
        params: Ref.input([]),
        validator: flow,
        node_path: ["child"]
      )

    output =
      Jido.Exec.Node.Output.new(
        id: :output,
        name: "child_output",
        output: flow.output,
        effect_order: [],
        validator: flow,
        parent_component: "child"
      )

    with {:ok, frame} <- Jido.Exec.Node.Input.resolve(input, Jido.Exec.Frame.new(params), %{}) do
      case Jido.Exec.Node.Output.run(output, frame, %Context{}) do
        %Result{status: :value, value: parent} ->
          {:ok, Jido.Exec.Frame.resolver_state(parent, %{}).results["child"]}

        %Result{status: :failure, error: error} ->
          {:error, error}
      end
    end
  end
end
