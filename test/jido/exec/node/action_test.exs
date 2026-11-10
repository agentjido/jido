defmodule Jido.Exec.Node.ActionTest do
  use Covenant.Case, component: "jido_action.boundary", async: true

  alias Jido.Exec.Node.Action
  alias Jido.Instruction

  alias Jido.Test.Action.Fixtures.Actions.{
    Add,
    BasicAction,
    EchoParamsAction,
    ErrorAction,
    ExtrasAction,
    UnsupportedResult
  }

  alias Runic.Workflow
  alias Runic.Workflow.{Fact, Invokable}

  defmodule ValidatorProbe do
    @behaviour Jido.Action
    def validate_params(%{input_validation: result}), do: result
    def validate_params(params), do: {:ok, params}
    def validate_output(%{output_validation: result}), do: result
    def validate_output(output), do: {:ok, output}

    def run(params, context) do
      send(context.observer, {context.token, :callback, params})
      output = if context[:wrap], do: %{params: params}, else: params
      {:ok, output, [:request]}
    end
  end

  @tag obligation: ["jido_action.boundary.I1", "jido_action.boundary.I3"]
  test "custom validator success must contain a map or a valid output envelope" do
    for phase <- [:input, :output],
        target <- [ValidatorProbe, boundary_flow(ValidatorProbe)] do
      token = make_ref()
      key = if phase == :input, do: :input_validation, else: :output_validation
      params = %{key => {:ok, 42}}

      assert {:error, %Jido.Error.InternalError{} = error} =
               Jido.Exec.run(target, params, %{observer: self(), token: token})

      assert error.message == "Action validator returned an invalid value"
      assert error.details.action == ValidatorProbe
      assert error.details.phase == phase
      assert error.details.return == {:ok, 42}
      assert error.details.reason == :invalid_validator_return

      if phase == :input do
        refute_received {^token, :callback, _}
      else
        assert_received {^token, :callback, ^params}
      end
    end
  end

  @tag obligation: ["jido_action.boundary.I3", "jido_action.boundary.I4"]
  test "custom output validators cannot pass a malformed output envelope" do
    invalid = %Jido.Action.Output{kind: :stream, value: 42, meta: %{}}

    for target <- [ValidatorProbe, boundary_flow(ValidatorProbe)] do
      token = make_ref()
      params = %{output_validation: {:ok, invalid}}

      assert {:error, %Jido.Error.ValidationError{} = error} =
               Jido.Exec.run(target, params, %{observer: self(), token: token})

      assert error.message == "invalid action output envelope"
      assert error.details.value == invalid
      assert_received {^token, :callback, ^params}
    end
  end

  defmodule ConvertingOutput do
    @behaviour Jido.Action
    def validate_params(params), do: {:ok, params}
    def validate_output(output), do: {:ok, %{converted: output}}
    def run(%{output: output}, _context), do: {:ok, output, [:request]}
  end

  defmodule PreservedValue do
    defstruct [:value]
  end

  defmodule PreservedOutput do
    use Jido.Action,
      name: "preserved_output",
      schema: Jido.Joi.object(%{value: Jido.Joi.any()}),
      output_schema: Jido.Joi.struct(PreservedValue, %{value: Jido.Joi.any()}, coerce: true)

    @impl true
    def run(%{value: value}, _context) do
      {:ok, Jido.Action.Output.preserve(%PreservedValue{value: value})}
    end
  end

  defmodule PreservedOutputFlow do
    use Jido.Flow,
      name: "preserved_output_flow",
      output_schema: Jido.Joi.struct(PreservedValue, %{value: Jido.Joi.integer()}, coerce: true)

    flow do
      step "preserve", action: PreservedOutput, params: input([])
      output result("preserve")
    end
  end

  @tag obligation: ["jido_action.boundary.I3", "jido_action.boundary.I4"]
  test "a preserved output keeps its validated root struct through a Flow" do
    expected = Jido.Action.Output.preserve(%PreservedValue{value: 7})

    data_flow =
      %{boundary_flow(PreservedOutput) | output_schema: PreservedOutputFlow.output_schema()}

    for target <- [PreservedOutput, PreservedOutputFlow, data_flow] do
      assert Jido.Exec.run(target, %{value: 7}) == {:ok, expected}
    end

    assert {:ok, %Jido.Action.Output{value: %PreservedValue{value: "invalid"}}} =
             Jido.Exec.run(PreservedOutput, %{value: "invalid"})

    for target <- [PreservedOutputFlow, data_flow] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Jido.Exec.run(target, %{value: "invalid"})
    end
  end

  @tag obligation: ["jido_action.boundary.I3", "jido_action.boundary.I4"]
  test "an output validator cannot conceal an invalid callback success value" do
    invalid = %Jido.Action.Output{kind: :batch, value: [1 | :tail], meta: %{}}

    for target <- [ConvertingOutput, boundary_flow(ConvertingOutput)] do
      assert {:error, %Jido.Error.ValidationError{} = scalar_error} =
               Jido.Exec.run(target, %{output: 42})

      assert scalar_error.message == "Action output validation must return a map"
      assert scalar_error.details.value == 42
      assert scalar_error.details.module == ConvertingOutput
      assert scalar_error.details.context == "Action output"

      assert {:error, %Jido.Error.ValidationError{} = envelope_error} =
               Jido.Exec.run(target, %{output: invalid})

      assert envelope_error.message == "invalid action output envelope"
      assert envelope_error.details.value == invalid

      assert {:ok, %{converted: %{value: 1}}, [:request]} =
               Jido.Exec.run(target, %{output: %{value: 1}})
    end
  end

  @tag obligation: "jido_action.boundary.I1"
  test "a validator map success keeps input structs separate from output envelope rules" do
    input = %Jido.Action.Output{kind: :input_data, value: 42, meta: %{}}
    token = make_ref()
    params = %{input_validation: {:ok, input}}

    assert {:ok, %{params: ^input}, [:request]} =
             Jido.Exec.run(ValidatorProbe, params, %{observer: self(), token: token, wrap: true})

    assert_received {^token, :callback, ^input}
  end

  defmodule ReturnProbe do
    @behaviour Jido.Action
    def validate_params(params), do: {:ok, params}
    def validate_output(output), do: {:ok, output}
    def run(%{reply: reply}, _context), do: reply
  end

  @tag obligation: ["jido_action.boundary.I1", "jido_action.boundary.I3"]
  test "validator failures use the shared error fields" do
    for phase <- [:input, :output],
        reply <- [{:error, :bad}, :ok],
        target <- [ValidatorProbe, boundary_flow(ValidatorProbe)] do
      token = make_ref()
      key = if phase == :input, do: :input_validation, else: :output_validation
      params = %{key => reply}

      assert {:error, error} =
               Jido.Exec.run(target, params, %{observer: self(), token: token})

      if reply == :ok do
        assert %Jido.Error.InternalError{} = error
        assert error.message == "Action validator returned an invalid value"
        assert error.details.action == ValidatorProbe
        assert error.details.phase == phase
        assert error.details.return == :ok
        assert error.details.reason == :invalid_validator_return
      else
        assert %Jido.Error.ValidationError{kind: :action, subject: ValidatorProbe} = error
        assert error.message == "Action #{phase} validation failed"
        assert error.details.phase == phase
        assert error.details.reason == :bad
      end

      if phase == :input,
        do: refute_received({^token, :callback, _}),
        else: assert_received({^token, :callback, ^params})
    end
  end

  @tag obligation: ["jido_action.boundary.I1", "jido_action.boundary.I3"]
  test "validator exception errors retain the original exception" do
    original = Jido.Error.validation_error("original", %{marker: :preserved})

    for phase <- [:input, :output] do
      token = make_ref()
      key = if phase == :input, do: :input_validation, else: :output_validation
      params = %{key => {:error, original}}

      assert {:error, ^original} =
               Jido.Exec.run(ValidatorProbe, params, %{observer: self(), token: token})
    end
  end

  @tag obligation: "jido_action.boundary.I2"
  test "callback errors retain exact messages reasons and failure details" do
    continuation = {:continue, %{value: 1}, Add}

    for target <- [ReturnProbe, boundary_flow(ReturnProbe)] do
      for reason <- ["rejected", :rejected, {:rejected, 42}],
          reply <- [{:error, reason}, {:error, reason, [:discard]}] do
        assert {:error, %Jido.Error.ExecutionError{} = error} =
                 Jido.Exec.run(target, %{reply: reply})

        expected =
          if is_binary(reason),
            do: reason,
            else: if(is_atom(reason), do: Atom.to_string(reason), else: inspect(reason))

        assert error.message == expected
        assert error.details.action == ReturnProbe
        assert error.phase == :run
        assert error.details.reason == reason
      end

      for {reply, message, reason} <- [
            {continuation, "Action continuations are not supported by Runic execution", :unsupported_continuation},
            {:bad_return, "Action returned an invalid value", :invalid_return}
          ] do
        assert {:error, %Jido.Error.ExecutionError{} = error} =
                 Jido.Exec.run(target, %{reply: reply})

        assert error.message == message
        assert error.details.action == ReturnProbe
        assert error.phase == :run
        assert error.details.return == reply
        assert error.details.reason == reason
      end
    end
  end

  @tag obligation: "jido_action.boundary.I4"
  test "invalid effect lists retain their rejected value and Action detail" do
    for target <- [ReturnProbe, boundary_flow(ReturnProbe)],
        effects <- [nil, %{}, [:request | :tail]] do
      assert {:error, %Jido.Error.ExecutionError{} = error} =
               Jido.Exec.run(target, %{reply: {:ok, %{}, effects}})

      assert error.message == "Action returned an invalid effects list"
      assert error.details.action == ReturnProbe
      assert error.phase == :run
      assert error.details.reason == :invalid_effects
      assert error.details.effects == effects
    end
  end

  @tag obligation: [
         "jido_action.boundary.I1",
         "jido_action.boundary.I2",
         "jido_action.boundary.I3"
       ]
  test "original callback and validator stacktraces remain in both documented fields" do
    alias Jido.Test.Action.Fixtures.Actions.{StacktraceAction, StacktraceValidationAction}

    for {action, mode, phase, frame} <- [
          {StacktraceAction, :raise, :run, :raise_from_action},
          {StacktraceAction, :throw, :run, :throw_from_action},
          {StacktraceAction, :exit, :run, :exit_from_action},
          {StacktraceValidationAction, :input, :input, :raise_from_input_validator},
          {StacktraceValidationAction, :output, :output, :raise_from_output_validator}
        ] do
      assert {:error, %Jido.Error.ExecutionError{} = error} =
               Jido.Exec.run(action, %{mode: mode})

      assert error.details.action == action
      assert error.phase == phase
      assert %Splode.Stacktrace{stacktrace: frames} = error.stacktrace
      assert frames == error.details.stacktrace
      assert Enum.any?(frames, &match?({^action, ^frame, 0, _}, &1))

      if mode in [:throw, :exit] do
        assert error.message == "Action run #{mode}"
        assert error.details.kind == mode

        assert error.details.reason ==
                 if(mode == :throw, do: :stacktrace_probe_thrown, else: :stacktrace_probe_exited)
      else
        assert error.details.exception == RuntimeError
      end
    end
  end

  @tag obligation: "jido_action.boundary.I5"
  test "native root input overrides Instruction params and wraps scalar input" do
    instruction = Instruction.new!(target: EchoParamsAction, params: %{fixed: 1, value: :before})
    node = Action.new(instruction, name: "merge")
    workflow = Workflow.new() |> Workflow.add(node)

    for {input, expected} <- [
          {%{value: :after, extra: true}, %{fixed: 1, value: :after, extra: true}},
          {42, %{fixed: 1, value: :before, input: 42}}
        ] do
      {:ok, runnable} = Invokable.prepare(node, workflow, Fact.new(value: input))
      executed = Invokable.execute(node, runnable)
      assert executed.status == :completed
      assert executed.result.value == expected
    end
  end

  @tag obligation: "jido_action.boundary.I5"
  test "Action components expose native ports connections and reconstructed result ports" do
    instruction = Instruction.new!(target: Add)
    node = Action.new(instruction, id: :public_id, name: "named")
    parent = Action.new(Instruction.new!(target: EchoParamsAction), name: "parent")

    assert Runic.Component.connectable?(node, parent) == true
    assert [in: [type: :any, doc: input_doc, schema: input_schema]] = Runic.Component.inputs(node)

    assert [out: [type: :any, doc: output_doc, schema: output_schema]] =
             Runic.Component.outputs(node)

    assert is_binary(input_doc)
    assert is_binary(output_doc)
    assert input_schema == Add.authoring_contract()["input_schema"]
    assert output_schema == Add.authoring_contract()["output_schema"]

    workflow = Runic.Transmutable.to_workflow(node)
    assert workflow.name == "named"
    assert workflow.output_ports == [result: [type: :any, from: "named"]]
    assert Workflow.get_component(workflow, {"named", :action}) == [node]

    second = Action.new(Instruction.new!(target: EchoParamsAction), name: "second")

    joined =
      Workflow.new()
      |> Workflow.add(parent)
      |> Workflow.add(second)
      |> Workflow.add(node, to: ["parent", "second"])

    assert Workflow.get_component(joined, "named") == node

    assert Enum.any?(joined.graph.vertices, fn {_, value} ->
             match?(%Runic.Workflow.Join{}, value)
           end)

    {rebuilt, []} = node |> Runic.Component.source() |> Code.eval_quoted()
    assert rebuilt == node
  end

  @tag obligation: "jido_action.boundary.I5"
  test "native identity distinguishes targets and IDs while excluding call data" do
    first = Action.new(Instruction.new!(target: Add), id: :first)
    other_target = Action.new(Instruction.new!(target: EchoParamsAction), id: :first)
    assert first.hash != other_target.hash

    forced_version = <<1, 2, 3>>

    forced_add =
      Action.new(Instruction.new!(target: Add), id: :forced, target_version: forced_version)

    forced_echo =
      Action.new(Instruction.new!(target: EchoParamsAction),
        id: :forced,
        target_version: forced_version
      )

    assert forced_add.hash != forced_echo.hash

    changed_version =
      Action.new(Instruction.new!(target: Add),
        id: :forced,
        target_version: <<4, 5, 6>>
      )

    assert forced_add.hash != changed_version.hash

    for {left, right} <- [{:left, :right}, {"left", "right"}] do
      a = Action.new(Instruction.new!(target: Add), id: left)
      b = Action.new(Instruction.new!(target: Add), id: right)
      assert a.hash != b.hash
      assert Runic.Identity.Canonical.encode!(a) != Runic.Identity.Canonical.encode!(b)
    end

    changed_call =
      Action.new(Instruction.new!(target: Add, params: %{value: 2}, context: %{runtime: self()}),
        id: :first
      )

    assert first.hash == changed_call.hash

    assert Runic.Identity.Canonical.encode!(first) ==
             Runic.Identity.Canonical.encode!(changed_call)
  end

  @tag obligation: "jido_action.boundary.I5"
  test "root compilation retains local term IDs without putting them in the native hash document" do
    for id <- [self(), make_ref()] do
      workflow = Jido.Exec.compile!(Add, id: id)
      node = Workflow.get_component(workflow, "add_one")
      assert node.id == id
      assert %Runic.Identity{domain: :component_definition} = node.hash
      {rebuilt, []} = node |> Runic.Component.source() |> Code.eval_quoted()
      assert rebuilt.id == id
      assert rebuilt.hash == node.hash
    end
  end

  @tag obligation: "jido_action.boundary.I5"
  test "native construction rejects a wrong Instruction kind and unresolved target" do
    instruction = Instruction.new!(target: Add)

    assert_raise Jido.Error.ValidationError, fn ->
      Action.new(%{instruction | target: Enum})
    end

    assert_raise ArgumentError, "expected an Action Instruction, got: :flow", fn ->
      Action.new(%{instruction | kind: :flow})
    end
  end

  @tag obligation: "jido_action.boundary.I5"
  test "an Action Instruction becomes a stable Action" do
    instruction = Instruction.new!(target: Add, params: %{amount: 2})

    first = Runic.Transmutable.to_component(instruction)
    second = Runic.Transmutable.to_component(instruction)

    assert %Action{instruction: ^instruction} = first
    assert first.hash == second.hash
    assert Runic.Component.hash(first) == first.hash
  end

  @tag obligation: "jido_action.boundary.I5"
  test "Action schemas are available through the Runic Component ports" do
    node = Add |> then(&Instruction.new!(target: &1)) |> Runic.Transmutable.to_component()

    assert Runic.Component.inputs(node)[:in][:schema] == Add.authoring_contract()["input_schema"]

    assert Runic.Component.outputs(node)[:out][:schema] ==
             Add.authoring_contract()["output_schema"]
  end

  @tag obligation: "jido_action.boundary.I5"
  test "Runic prepares, executes, and applies an Action" do
    node = Action.new(Instruction.new!(target: Add, params: %{amount: 2}), name: "add")
    workflow = Workflow.new(name: "one_action") |> Workflow.add(node)
    fact = Fact.new(value: %{value: 3})

    assert {:ok, runnable} = Invokable.prepare(node, workflow, fact)
    assert runnable.status == :pending

    executed = Invokable.execute(node, runnable)
    assert executed.status == :completed
    assert %Fact{value: %{value: 5}} = executed.result

    applied = Workflow.apply_runnable(workflow, executed)
    assert Workflow.raw_productions(applied, "add") == [%{value: 5}]
  end

  @tag obligation: "jido_action.boundary.I5"
  test "an Action participates in a native SingleOutput batch" do
    node = Action.new(Instruction.new!(target: Add, params: %{amount: 2}), name: "item")
    batch = Runic.batch(node, name: "batch")
    definition = Workflow.new() |> Workflow.add(batch)
    rebuilt = definition |> Workflow.build_log() |> Workflow.from_log()
    {completed, observation} = Workflow.execute(rebuilt, [%{value: 1}, %{value: 3}])

    assert observation.quiescent?

    assert [id] = Runic.Workflow.Batch.invocations(completed, batch)
    assert {:ok, outcomes} = Runic.Workflow.Batch.outcomes(completed, batch, id)

    assert Enum.map(outcomes, & &1.value) == [%{value: 3}, %{value: 5}]
    assert Enum.all?(outcomes, &(&1.status == :completed))
  end

  @tag obligation: ["jido_action.boundary.I4", "jido_action.boundary.I5"]
  test "successful output keeps application metadata and effects through the native lifecycle" do
    node = Action.new(Instruction.new!(target: ExtrasAction), name: "effects")

    workflow =
      Workflow.new()
      |> Workflow.add(node)
      |> Workflow.put_run_context(%{_global: %{trace_id: "current"}})

    metadata = %{domain: :input, jido: %{effects: [:prior]}, runic: %{internal: :input}}
    fact = Fact.new(value: %{value: 3}, meta: metadata)
    {:ok, runnable} = Invokable.prepare(node, workflow, fact)
    executed = Invokable.execute(node, runnable)

    assert executed.status == :completed
    assert executed.result.value == %{value: 3}

    assert executed.result.meta == %{
             domain: :input,
             jido: %{effects: [:prior, %{trace_id: "current"}]}
           }

    assert executed.result.ancestry == {node.hash, fact.hash}
  end

  @tag obligation: ["jido_action.boundary.I4", "jido_action.boundary.I5"]
  test "native completion preserves local values from marked and wrapped input Facts" do
    node = Action.new(Instruction.new!(target: EchoParamsAction), name: "local")
    workflow = Workflow.new() |> Workflow.add(node)
    params = %{owner: self(), reference: make_ref(), uri: URI.parse("/local")}

    for fact <- [
          Jido.Exec.Fact.local_root(params),
          Fact.new(value: Jido.Exec.Fact.local_value(params))
        ] do
      {:ok, runnable} = Invokable.prepare(node, workflow, fact)
      executed = Invokable.execute(node, runnable)

      assert executed.status == :completed
      assert Jido.Exec.Fact.value(executed.result) == params
      assert executed.result.meta.jido.identity_mode == :local
    end
  end

  @tag obligation: "jido_action.boundary.I5"
  test "native hooks defer graph changes until successful application" do
    node = Action.new(Instruction.new!(target: Add, params: %{amount: 2}), name: "hooks")
    owner = self()

    hook = fn event, _context ->
      send(owner, {:hook, event.timing})

      {:apply,
       fn workflow ->
         send(owner, {:applied, event.timing})
         workflow
       end}
    end

    workflow =
      Workflow.new()
      |> Workflow.add(node)
      |> Map.put(:before_hooks, %{node.hash => [hook]})
      |> Map.put(:after_hooks, %{node.hash => [hook]})

    {:ok, runnable} = Invokable.prepare(node, workflow, Fact.new(value: %{value: 3}))
    executed = Invokable.execute(node, runnable)
    assert executed.status == :completed
    assert_receive {:hook, :before}
    assert_receive {:hook, :after}
    refute_received {:applied, _timing}

    Workflow.apply_runnable(workflow, executed)
    assert_receive {:applied, :before}
    assert_receive {:applied, :after}
  end

  @tag obligation: "jido_action.boundary.I2"
  test "hook failures publish no Fact and discard deferred changes" do
    node = Action.new(Instruction.new!(target: ExtrasAction), name: "failed_hooks")
    owner = self()

    before_hook = fn _event, _context ->
      {:apply,
       fn workflow ->
         send(owner, :applied)
         workflow
       end}
    end

    for timing <- [:before_hooks, :after_hooks] do
      workflow =
        Workflow.new()
        |> Workflow.add(node)
        |> Map.put(:before_hooks, %{node.hash => [before_hook]})
        |> Map.put(timing, %{node.hash => [fn _event, _context -> {:error, :rejected} end]})

      {:ok, runnable} = Invokable.prepare(node, workflow, Fact.new(value: %{value: 3}))
      executed = Invokable.execute(node, runnable)
      assert executed.status == :failed
      assert executed.result == nil
      assert executed.events == nil
      assert executed.hook_apply_fns == nil
      refute_received :applied
    end
  end

  @tag obligation: "jido_action.boundary.I1"
  test "input validation fails the Runnable" do
    node = Action.new(Instruction.new!(target: BasicAction), name: "basic")
    workflow = Workflow.new() |> Workflow.add(node)
    fact = Fact.new(value: %{value: "bad"})

    {:ok, runnable} = Invokable.prepare(node, workflow, fact)
    executed = Invokable.execute(node, runnable)

    assert executed.status == :failed
    assert %Jido.Error.ValidationError{} = executed.error
  end

  @tag obligation: "jido_action.boundary.I2"
  test "an Action exception fails the Runnable with a structured error" do
    node = Action.new(Instruction.new!(target: ErrorAction), name: "error")
    workflow = Workflow.new() |> Workflow.add(node)
    fact = Fact.new(value: %{error_type: :runtime})

    {:ok, runnable} = Invokable.prepare(node, workflow, fact)
    executed = Invokable.execute(node, runnable)

    assert executed.status == :failed
    assert %Jido.Error.ExecutionError{phase: :run} = executed.error
  end

  @tag obligation: "jido_action.boundary.I2"
  test "an invalid Action return fails the Runnable" do
    node = Action.new(Instruction.new!(target: UnsupportedResult), name: "unsupported")
    workflow = Workflow.new() |> Workflow.add(node)
    fact = Fact.new(value: %{})

    {:ok, runnable} = Invokable.prepare(node, workflow, fact)
    executed = Invokable.execute(node, runnable)

    assert executed.status == :failed

    assert %Jido.Error.ExecutionError{details: %{reason: :invalid_return}} =
             executed.error
  end

  @tag obligation: "jido_action.boundary.I5"
  test "normal atoms keep Runic's normal Transmutable behavior" do
    refute match?(%Action{}, Runic.Transmutable.to_component(:ordinary_value))
  end

  defp boundary_flow(action) do
    Jido.Flow.new!(%{
      name: "validator_boundary",
      components: [%{kind: :step, name: "work", action: action, params: Jido.Flow.Ref.input([])}],
      output: Jido.Flow.Ref.result("work")
    })
  end
end
