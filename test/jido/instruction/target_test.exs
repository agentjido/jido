defmodule JidoActionTest.Instruction.TargetTest do
  use Covenant.Case, component: "jido_action.instruction", async: false
  @moduletag obligation: "jido_action.instruction.I5"

  alias Jido.{Exec, Instruction}
  alias Jido.Flow.Ref
  alias JidoActionTest.Fixtures.MathFlow
  alias JidoActionTest.Fixtures.Actions.{Add, MissingValidateParams, MissingValidateOutput}

  # These targets are defined in test/support/fixtures/action/missing_callbacks.exs.
  alias __MODULE__.{Ambiguous, MissingActionRun, MissingFlowDefinition}

  defmodule CallbackOnly do
    def run(params, _context), do: {:ok, params}
    def validate_params(params), do: {:ok, params}
    def validate_output(output), do: {:ok, output}
  end

  defmodule FlowWithoutRun do
    @behaviour Jido.Flow

    @impl true
    def flow, do: MathFlow.flow()
    @impl true
    defdelegate validate_params(params), to: MathFlow
    @impl true
    defdelegate validate_output(output), to: MathFlow
  end

  defmodule ContinueToFlow do
    use Jido.Action, name: "continue_to_flow_without_run"

    @impl true
    def run(params, _context), do: {:continue, params, FlowWithoutRun}
  end

  test "Action and Flow behaviours own their execution callbacks" do
    assert {:run, 2} in Jido.Action.behaviour_info(:callbacks)
    assert {:validate_params, 1} in Jido.Action.behaviour_info(:callbacks)
    assert {:validate_output, 1} in Jido.Action.behaviour_info(:callbacks)

    assert {:flow, 0} in Jido.Flow.behaviour_info(:callbacks)
    assert {:validate_params, 1} in Jido.Flow.behaviour_info(:callbacks)
    assert {:validate_output, 1} in Jido.Flow.behaviour_info(:callbacks)
  end

  test "generated modules share the Action behaviour and retain their target kind" do
    assert behaviours(Add) == [Jido.Action]
    assert behaviours(MathFlow) == [Jido.Action]
    assert Add.__jido_authoring_kind__() == :action
    assert MathFlow.__jido_authoring_kind__() == :flow
  end

  test "resolution keeps the exact target and current kind" do
    flow = MathFlow.flow()

    for {target, kind} <- [{Add, :action}, {MathFlow, :flow}, {flow, :flow}] do
      assert {:ok, ^kind} = Instruction.target_kind(target)
      assert {:ok, %Instruction{kind: ^kind, target: ^target}} = Instruction.resolve(target)
      assert :ok = Instruction.validate(target)
    end
  end

  test "resolution ignores a stale kind in a raw Instruction" do
    stale = %Instruction{kind: :flow, target: Add, params: %{value: 1}}

    assert {:ok, %Instruction{kind: :action, target: Add}} = Instruction.resolve(stale)
    assert Exec.run(stale) == {:ok, %{value: 2}}
  end

  test "construction checks an explicit kind against the current target" do
    assert {:ok, %Instruction{kind: :action, target: Add}} =
             Instruction.new(kind: :action, target: Add)

    assert {:error, %Jido.Action.Error.ConfigurationError{details: details} = error} =
             Instruction.new(kind: :flow, target: Add)

    assert details == %{declared: :flow, actual: :action, reason: :target_kind_changed}
    assert byte_size(error.message) > 0
  end

  @tag obligation: "jido_action.instruction.I4"
  test "nested Instructions flatten with right-biased shallow merges" do
    inner =
      Instruction.new!(
        target: Add,
        params: %{value: 1, nested: %{inner: true}},
        context: %{trace: "inner"},
        metadata: %{source: :inner}
      )

    outer = %Instruction{
      target: inner,
      params: %{amount: 2, nested: %{outer: true}},
      context: %{tenant: "acme"},
      metadata: %{source: :outer}
    }

    assert {:ok, instruction} = Instruction.resolve(outer, %{amount: 3}, %{trace: "call"})
    assert instruction.target == Add
    assert instruction.kind == :action
    assert instruction.params == %{value: 1, amount: 3, nested: %{outer: true}}
    assert instruction.context == %{trace: "call", tenant: "acme"}
    assert instruction.metadata == %{source: :outer}
  end

  @tag obligation: "jido_action.instruction.I2"
  test "canonical Flow components reject bound Instructions" do
    action = Instruction.new!(target: Add, params: %{amount: 2})
    flow = Instruction.new!(target: MathFlow, params: %{value: 2})

    assert {:error, %Jido.Flow.Error.InvalidDefinitionError{}} =
             JidoActionTest.FlowComponent.step(name: "action", action: action)

    assert {:error, %Jido.Flow.Error.InvalidDefinitionError{}} =
             JidoActionTest.FlowComponent.subflow(name: "flow", flow: flow)
  end

  test "callbacks without a target behaviour do not classify a module" do
    assert {:error, %Jido.Action.Error.ConfigurationError{details: details}} =
             Instruction.resolve(CallbackOnly)

    assert details == %{target: CallbackOnly, reason: :missing_behaviour}

    assert {:error, %Jido.Action.Error.ConfigurationError{details: ^details}} =
             Instruction.target_kind(CallbackOnly)
  end

  test "a module cannot implement both target behaviours" do
    assert {:error, %Jido.Action.Error.ConfigurationError{details: details} = error} =
             Instruction.resolve(Ambiguous)

    assert details == %{target: Ambiguous, reason: :ambiguous_behaviour}
    assert byte_size(error.message) > 0

    assert {:error, %Jido.Action.Error.ConfigurationError{details: ^details}} =
             Instruction.target_kind(Ambiguous)
  end

  @tag obligation: "jido_action.instruction.I6"
  test "validation checks callbacks for the resolved kind" do
    for {target, callback} <- [
          {MissingActionRun, "run/2"},
          {MissingFlowDefinition, "flow/0"},
          {MissingValidateParams, "validate_params/1"},
          {MissingValidateOutput, "validate_output/1"}
        ] do
      assert {:error, %Jido.Action.Error.InvalidInputError{} = error} =
               Instruction.validate(target)

      assert error.message == "module is not a valid Instruction target"
      assert error.details == %{target: target, reason: "missing #{callback}"}
    end
  end

  test "unavailable module targets return configuration errors" do
    target = Module.concat(__MODULE__, "Unavailable#{System.unique_integer([:positive])}")
    template = Instruction.template(:action, target)

    for result <- [
          Instruction.target_kind(target),
          Instruction.resolve(target),
          Instruction.new(target: target),
          Instruction.bind(template, %{}, %{}),
          Instruction.validate(target)
        ] do
      assert {:error, %Jido.Action.Error.ConfigurationError{} = error} = result
      assert error.details == %{target: target, reason: :nofile}
      assert String.contains?(error.message, inspect(target))
    end
  end

  @tag obligation: "jido_action.instruction.I6"
  test "resolved validation rejects malformed kinds and targets" do
    for instruction <- [
          %Instruction{kind: nil, target: Add},
          %Instruction{kind: :worker, target: Add},
          %Instruction{kind: :action, target: nil},
          %Instruction{kind: :action, target: "not a module"},
          %Instruction{kind: :action, target: MathFlow.flow()}
        ] do
      assert {:error, %Jido.Action.Error.InvalidInputError{} = error} =
               Instruction.validate_resolved(instruction)

      assert error.details == %{instruction: instruction, reason: :invalid_target}
      assert byte_size(error.message) > 0
    end
  end

  @tag obligation: "jido_action.instruction.I6"
  @tag :tmp_dir
  test "resolved callback validation loads an unloaded module", %{tmp_dir: dir} do
    target = Module.concat(__MODULE__, "Unloaded#{System.unique_integer([:positive])}")

    [{^target, beam}] =
      Code.compile_string("""
      defmodule #{inspect(target)} do
        @behaviour Jido.Action
        @impl true
        def run(_params, _context), do: raise("must not run")
        @impl true
        def validate_params(_params), do: raise("must not validate input")
        @impl true
        def validate_output(_output), do: raise("must not validate output")
      end
      """)

    File.write!(Path.join(dir, Atom.to_string(target) <> ".beam"), beam)
    true = Code.prepend_path(dir)

    on_exit(fn ->
      :code.purge(target)
      :code.delete(target)
      Code.delete_path(dir)
    end)

    :code.purge(target)
    :code.delete(target)
    assert :code.is_loaded(target) == false
    assert :ok = Instruction.validate_resolved(%Instruction{kind: :action, target: target})
    assert :code.is_loaded(target) != false
  end

  @tag obligation: [
         "jido_action.instruction.I2",
         "jido_action.instruction.I5",
         "jido_action.instruction.I6"
       ]
  test "resolution and validation read reloaded behavior without executing callbacks" do
    target = Module.concat(__MODULE__, "Reloaded#{System.unique_integer([:positive])}")

    on_exit(fn ->
      :code.purge(target)
      :code.delete(target)
    end)

    Code.compile_string("""
    defmodule #{inspect(target)} do
      @behaviour Jido.Action
      @impl true
      def run(_params, _context), do: raise("must not run")
      @impl true
      def validate_params(_params), do: raise("must not validate input")
      @impl true
      def validate_output(_output), do: raise("must not validate output")
    end
    """)

    retained = Instruction.new!(target: target)
    action_template = Instruction.template(:action, target)
    assert retained.kind == :action
    assert :ok = Instruction.validate(retained)

    :code.purge(target)
    :code.delete(target)

    Code.compile_string("""
    defmodule #{inspect(target)} do
      @behaviour Jido.Flow
      @impl true
      def flow, do: raise("must not build a Flow")
      @impl true
      def validate_params(_params), do: raise("must not validate input")
      @impl true
      def validate_output(_output), do: raise("must not validate output")
    end
    """)

    assert {:ok, %Instruction{kind: :flow, target: ^target}} = Instruction.resolve(retained)
    assert :ok = Instruction.validate(retained)

    assert {:error, %Jido.Action.Error.ConfigurationError{} = error} =
             Instruction.bind(action_template, %{}, %{})

    assert error.details == %{declared: :action, actual: :flow, reason: :target_kind_changed}

    assert {:ok, %Instruction{kind: :flow}} =
             Instruction.bind(Instruction.template(:flow, target), %{}, %{})
  end

  @tag obligation: ["jido_action.instruction.I5", "jido_action.instruction.I6"]
  test "a Flow without run/2 executes through all public target forms" do
    input = %{value: 3}
    expected = {:ok, %{value: 8}}
    instruction = Instruction.new!(target: FlowWithoutRun, params: input)

    parent =
      JidoActionTest.FlowBuilder.new!(
        name: "flow_without_run_parent",
        components: [
          JidoActionTest.FlowComponent.subflow!(
            name: "child",
            flow: FlowWithoutRun,
            params: Ref.input([])
          )
        ],
        output: Ref.result("child")
      )

    assert Exec.run(FlowWithoutRun, input) == expected
    assert Exec.run(instruction) == expected
    assert Exec.run(parent, input) == expected

    assert {:error, %{details: %{reason: :unsupported_continuation}}} =
             Exec.run(ContinueToFlow, input)
  end

  test "generated Flow run/2 delegates to Exec" do
    assert MathFlow.run(%{value: 3}, %{}) == Exec.run(MathFlow, %{value: 3})
    assert MathFlow.run(%{value: "bad"}, %{}) == Exec.run(MathFlow, %{value: "bad"})
  end

  defp behaviours(module) do
    module.__info__(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end
end
