defmodule JidoActionTest.InstructionTest do
  use ExUnit.Case, async: true

  alias Jido.Instruction
  alias JidoActionTest.Fixtures.MathFlow
  alias JidoActionTest.Fixtures.Actions.BasicAction

  defmodule InvalidKind do
    def __jido_kind__, do: :worker
  end

  defmodule RaisingKind do
    def __jido_kind__, do: raise("kind failed")
  end

  defmodule ThrowingKind do
    def __jido_kind__, do: throw(:kind_failed)
  end

  @tag obligation: "jido_action.instruction.I2"
  test "contains only target and call data" do
    assert Instruction.new!(target: BasicAction)
           |> Map.from_struct()
           |> Map.keys()
           |> Enum.sort() == [:context, :metadata, :params, :target]

    literal = {:%, [], [Instruction, {:%{}, [], [kind: :action, target: BasicAction]}]}
    assert_raise KeyError, fn -> Code.eval_quoted(literal) end
  end

  @tag obligation: "jido_action.instruction.I2"
  test "creates an Instruction with defaults and complete call data" do
    assert {:ok,
            %Instruction{
              target: BasicAction,
              params: %{},
              context: %{},
              metadata: %{}
            }} = Instruction.new(target: BasicAction)

    assert {:ok, instruction} =
             Instruction.new(%{
               target: BasicAction,
               params: [value: 42],
               context: [tenant: "acme"],
               metadata: [correlation_id: "req-1"]
             })

    assert instruction.params == %{value: 42}
    assert instruction.context == %{tenant: "acme"}
    assert instruction.metadata == %{correlation_id: "req-1"}
  end

  @tag obligation: "jido_action.instruction.I3"
  test "normalizes nil call maps and rejects invalid call data" do
    assert {:ok, instruction} =
             Instruction.new(target: BasicAction, params: nil, context: nil, metadata: nil)

    assert instruction.params == %{}
    assert instruction.context == %{}
    assert instruction.metadata == %{}

    for field <- [:params, :context, :metadata] do
      assert {:error, %Instruction.Error{details: %{field: ^field}}} =
               Instruction.new(%{field => 42, target: BasicAction})

      assert {:error, %Instruction.Error{details: %{field: ^field}}} =
               Instruction.new(%{field => [:not_a_keyword], target: BasicAction})
    end
  end

  @tag obligation: "jido_action.instruction.I3"
  test "normalizes compact single-Instruction forms" do
    assert {:ok, %Instruction{target: BasicAction}} = Instruction.normalize(BasicAction)

    assert {:ok,
            %Instruction{
              target: BasicAction,
              params: %{value: 42},
              context: %{},
              metadata: %{}
            }} = Instruction.normalize({BasicAction, %{value: 42}})

    assert {:ok,
            %Instruction{
              target: BasicAction,
              params: %{value: 42},
              context: %{tenant: "acme"},
              metadata: %{}
            }} = Instruction.normalize({BasicAction, [value: 42], [tenant: "acme"]})

    assert {:ok,
            %Instruction{
              target: BasicAction,
              params: %{value: 42},
              context: %{tenant: "acme"},
              metadata: %{request_id: "req-1"}
            }} =
             Instruction.normalize(
               {BasicAction, %{value: 42}, %{tenant: "acme"}, %{request_id: "req-1"}}
             )

    instruction = Instruction.new!(target: BasicAction, params: %{value: 42})
    assert {:ok, ^instruction} = Instruction.normalize(instruction)

    assert ^instruction = Instruction.normalize!(instruction)
  end

  @tag obligation: "jido_action.instruction.I3"
  test "rejects malformed compact Instruction forms" do
    assert {:error, %Instruction.Error{details: %{field: :params}}} =
             Instruction.normalize({BasicAction, :invalid})

    assert {:error, %Instruction.Error{details: %{field: :context}}} =
             Instruction.normalize({BasicAction, %{}, :invalid})

    assert {:error, %Instruction.Error{details: %{field: :metadata}}} =
             Instruction.normalize({BasicAction, %{}, %{}, :invalid})

    assert {:error, %Instruction.Error{details: %{reason: :input}}} =
             Instruction.normalize({BasicAction})

    assert {:error, %Instruction.Error{details: %{reason: :input}}} =
             Instruction.normalize([BasicAction])

    assert_raise Instruction.Error, fn ->
      Instruction.normalize!({BasicAction, %{}, %{}, :invalid})
    end
  end

  @tag obligation: "jido_action.instruction.I3"
  test "requires one direct module or struct target" do
    assert {:error, %Instruction.Error{details: %{field: :target}}} = Instruction.new(%{})

    for target <- [nil, true, "BasicAction", %{}] do
      assert {:error, %Instruction.Error{details: %{target: ^target}}} =
               Instruction.new(target: target)
    end

    nested = Instruction.new!(target: BasicAction)

    assert {:error, %Instruction.Error{details: %{target: ^nested}}} =
             Instruction.new(target: nested)

    assert {:error, %Instruction.Error{details: %{fields: [:unknown]}}} =
             Instruction.new(target: BasicAction, unknown: true)
  end

  @tag obligation: "jido_action.instruction.I3"
  test "construction is inert and raising construction preserves the error" do
    target = Module.concat(__MODULE__, "Unavailable#{System.unique_integer([:positive])}")
    assert :code.is_loaded(target) == false
    assert {:ok, %Instruction{target: ^target}} = Instruction.new(target: target)
    assert :code.is_loaded(target) == false

    assert_raise Instruction.Error, fn -> Instruction.new!(target: nil) end

    assert {:error, %Instruction.Error{details: %{reason: :attributes}}} =
             Instruction.new(:not_attributes)
  end

  @tag obligation: "jido_action.instruction.I4"
  test "derives Action and Flow types without retaining them" do
    flow = MathFlow.flow()

    for {target, kind} <- [{BasicAction, :action}, {MathFlow, :flow}, {flow, :flow}] do
      instruction = Instruction.new!(target: target)
      assert {:ok, ^kind} = Instruction.target_kind(target)
      assert {:ok, ^kind} = Instruction.target_kind(instruction)
    end

    assert BasicAction.__jido_kind__() == :action
    assert MathFlow.__jido_kind__() == :flow
    assert Jido.Flow.__jido_kind__() == :flow
  end

  @tag obligation: "jido_action.instruction.I4"
  test "contains invalid target markers and unavailable modules" do
    unavailable = Module.concat(__MODULE__, "Unavailable#{System.unique_integer([:positive])}")
    unavailable_struct = %{__struct__: unavailable}

    for {target, reason} <- [
          {String, :missing_kind},
          {InvalidKind, {:invalid_kind, :worker}},
          {unavailable, :nofile},
          {unavailable_struct, :nofile}
        ] do
      assert {:error, %Instruction.Error{details: %{target: ^target, reason: ^reason}}} =
               Instruction.target_kind(target)
    end

    assert {:error, %Instruction.Error{details: %{reason: {:kind_failure, :error, _error}}}} =
             Instruction.target_kind(RaisingKind)

    assert {:error,
            %Instruction.Error{
              details: %{reason: {:kind_failure, :throw, :kind_failed}}
            }} = Instruction.target_kind(ThrowingKind)

    assert {:error, %Instruction.Error{details: %{target: 42, reason: :invalid_target}}} =
             Instruction.target_kind(42)
  end

  @tag obligation: "jido_action.instruction.I5"
  test "does not expose template, binding, resolution, or executable validation APIs" do
    for {function, arity} <- [
          template: 2,
          bind: 4,
          resolve: 3,
          normalize!: 3,
          validate: 1,
          validate_resolved: 1
        ] do
      refute function_exported?(Instruction, function, arity)
    end
  end
end
