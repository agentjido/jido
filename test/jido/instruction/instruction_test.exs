defmodule JidoActionTest.InstructionTest do
  use Covenant.Case, component: "jido_action.instruction", async: true

  alias Jido.Instruction
  alias JidoActionTest.Fixtures.MathFlow

  alias JidoActionTest.Fixtures.Actions.{
    Add,
    BasicAction,
    MissingRun,
    MissingValidateParams,
    MissingValidateOutput
  }

  describe "template/3" do
    @describetag obligation: "jido_action.instruction.I2"

    test "creates an inert module template without loading the target" do
      target = Module.concat(__MODULE__, "NotLoaded#{System.unique_integer([:positive])}")

      assert :code.is_loaded(target) == false

      assert %Instruction{
               kind: :action,
               target: ^target,
               params: %{},
               context: %{},
               metadata: %{source: :stored}
             } = Instruction.template(:action, target, %{source: :stored})

      assert :code.is_loaded(target) == false
    end

    test "requires a declared kind, module atom, and metadata map" do
      assert_raise ArgumentError, ~r/kind/, fn ->
        apply(Instruction, :template, [:worker, BasicAction])
      end

      for target <- ["Elixir.MyApp.Action", nil, 42] do
        assert_raise ArgumentError, ~r/module atom/, fn ->
          apply(Instruction, :template, [:action, target])
        end
      end

      assert_raise ArgumentError, ~r/metadata/, fn ->
        apply(Instruction, :template, [:action, BasicAction, [source: :stored]])
      end
    end
  end

  describe "bind/4" do
    @describetag obligation: "jido_action.instruction.I2"

    test "binds and validates an Action template" do
      template =
        Instruction.template(:action, BasicAction, %{
          jido_flow: %{source: :authored},
          retained: true
        })

      assert {:ok, instruction} =
               Instruction.bind(
                 template,
                 %{value: 42},
                 %{tenant: "acme"},
                 %{jido_flow: %{occurrence: "one"}, runtime: true}
               )

      assert instruction == %Instruction{
               kind: :action,
               target: BasicAction,
               params: %{value: 42},
               context: %{tenant: "acme"},
               metadata: %{
                 jido_flow: %{occurrence: "one"},
                 retained: true,
                 runtime: true
               }
             }
    end

    test "binds and validates a Flow template" do
      template = Instruction.template(:flow, MathFlow)

      assert {:ok,
              %Instruction{
                kind: :flow,
                target: MathFlow,
                params: %{value: 2},
                context: %{},
                metadata: %{}
              }} = Instruction.bind(template, %{value: 2}, %{})
    end

    test "confirms the declared target kind" do
      template = Instruction.template(:flow, BasicAction)

      assert {:error,
              %Jido.Action.Error.ConfigurationError{
                details: %{
                  declared: :flow,
                  actual: :action,
                  reason: :target_kind_changed
                }
              }} = Instruction.bind(template, %{}, %{})
    end

    test "validates the executable callbacks" do
      for {target, callback} <- [
            {MissingRun, "run/2"},
            {MissingValidateParams, "validate_params/1"},
            {MissingValidateOutput, "validate_output/1"}
          ] do
        template = Instruction.template(:action, target)

        assert {:error, %Jido.Action.Error.InvalidInputError{} = error} =
                 Instruction.bind(template, %{}, %{})

        assert error.details == %{target: target, reason: "missing #{callback}"}
      end
    end

    test "keeps raw parameters for target input validation" do
      template = Instruction.template(:action, BasicAction)

      for params <- [[value: 1], nil, 123] do
        assert {:ok, %Instruction{params: ^params}} =
                 Instruction.bind(template, params, %{})
      end
    end

    test "requires map context and metadata" do
      template = Instruction.template(:action, BasicAction)

      for {context, metadata, field} <- [
            {[tenant: "acme"], %{}, :context},
            {%{}, [source: :runtime], :metadata}
          ] do
        assert {:error,
                %Jido.Action.Error.InvalidInputError{
                  message: message,
                  details: %{field: ^field, value: value, reason: :invalid_binding_data}
                }} = Instruction.bind(template, %{}, context, metadata)

        assert value === if(field == :context, do: context, else: metadata)
        assert String.contains?(message, Atom.to_string(field))
      end
    end

    test "rejects bound or malformed template values" do
      for {template, reason} <- [
            {nil, :invalid_template},
            {%{}, :invalid_template},
            {%Instruction{kind: nil, target: BasicAction}, :invalid_kind},
            {%Instruction{kind: :action, target: "BasicAction"}, :invalid_target},
            {%Instruction{kind: :action, target: nil}, :invalid_target},
            {%Instruction{kind: :action, target: BasicAction, params: %{value: 1}}, :bound_params},
            {%Instruction{kind: :action, target: BasicAction, context: %{tenant: "acme"}}, :bound_context},
            {%Instruction{kind: :action, target: BasicAction, metadata: nil}, :invalid_metadata},
            {%Instruction{kind: :action, target: BasicAction, metadata: []}, :invalid_metadata}
          ] do
        assert {:error, %Jido.Action.Error.InvalidInputError{} = error} =
                 Instruction.bind(template, %{}, %{})

        assert error.details == %{template: template, reason: reason}
        assert String.contains?(error.message, "template")
      end
    end
  end

  describe "new/1" do
    @describetag obligation: "jido_action.instruction.I3"

    test "exposes the resolved kind and four call-data fields" do
      assert Instruction.new!(target: BasicAction)
             |> Map.from_struct()
             |> Map.keys()
             |> Enum.sort() ==
               [:context, :kind, :metadata, :params, :target]
    end

    test "rejects removed fields in map and keyword constructors even when empty" do
      for {field, value} <- [
            action: BasicAction,
            flow: MathFlow,
            opts: [timeout: 10],
            action: nil,
            flow: nil,
            opts: [],
            opts: nil,
            id: "old"
          ],
          base <- [%{}, %{target: BasicAction}],
          attrs <- [Map.put(base, field, value), Map.to_list(Map.put(base, field, value))] do
        assert {:error, %Jido.Action.Error.InvalidInputError{details: details} = error} =
                 Instruction.new(attrs)

        assert details == %{fields: [field], reason: :removed_instruction_fields}
        assert byte_size(error.message) > 0
        refute Jido.Action.Error.retryable?(error)

        assert_raise Jido.Action.Error.InvalidInputError, error.message, fn ->
          Instruction.new!(attrs)
        end
      end
    end

    test "reports all removed fields in stable order" do
      attrs = %{target: BasicAction, opts: [], flow: nil, action: nil, id: "old"}

      assert {:error, %Jido.Action.Error.InvalidInputError{details: details}} =
               Instruction.new(attrs)

      assert details == %{
               fields: [:id, :action, :flow, :opts],
               reason: :removed_instruction_fields
             }
    end

    test "removed fields cannot appear in struct literals" do
      for field <- [:action, :flow, :opts] do
        literal = {:%, [], [Instruction, {:%{}, [], [{field, nil}]}]}
        assert_raise KeyError, fn -> Code.eval_quoted(literal) end
      end
    end

    test "creates an instruction with defaults" do
      assert {:ok, instruction} = Instruction.new(target: BasicAction)
      assert instruction.target == BasicAction
      assert instruction.params == %{}
      assert instruction.context == %{}
      assert instruction.metadata == %{}
    end

    test "creates an instruction with all fields" do
      assert {:ok, instruction} =
               Instruction.new(%{
                 target: BasicAction,
                 params: [value: 42],
                 context: [request_id: "req-1"],
                 metadata: [source: %{name: "api"}, tags: ["new"]]
               })

      assert instruction.target == BasicAction
      assert instruction.params == %{value: 42}
      assert instruction.context == %{request_id: "req-1"}
      assert instruction.metadata == %{source: %{name: "api"}, tags: ["new"]}
    end

    test "normalizes nil invocation maps" do
      assert {:ok, instruction} =
               Instruction.new(%{
                 target: BasicAction,
                 params: nil,
                 context: nil,
                 metadata: nil
               })

      assert instruction.params == %{}
      assert instruction.context == %{}
      assert instruction.metadata == %{}
    end

    test "stores Flow module targets" do
      assert {:ok, instruction} =
               Instruction.new(
                 target: MathFlow,
                 params: %{value: 2},
                 context: %{tenant: "acme"},
                 metadata: %{request: %{id: "req-1"}}
               )

      assert instruction.target == MathFlow
      assert instruction.params == %{value: 2}
      assert instruction.context == %{tenant: "acme"}
      assert instruction.metadata == %{request: %{id: "req-1"}}
    end

    test "stores runtime Flow values without conversion" do
      flow = MathFlow.flow()

      assert {:ok, instruction} =
               Instruction.new(
                 target: flow,
                 params: %{value: 2},
                 metadata: %{origin: :runtime}
               )

      assert instruction.target === flow
      assert instruction.metadata == %{origin: :runtime}
    end

    test "returns structured errors for missing and invalid targets" do
      assert {:error, %Jido.Action.Error.InvalidInputError{} = error} =
               Instruction.new(%{params: %{value: 1}})

      assert error.details == %{field: :target, reason: :missing}
      assert byte_size(error.message) > 0

      for target <- ["not_a_module", nil] do
        assert {:error, %Jido.Action.Error.ConfigurationError{details: details}} =
                 Instruction.new(%{target: target})

        assert details.target == target
      end
    end

    test "rejects invalid invocation maps" do
      assert {:error, %Jido.Action.Error.InvalidInputError{} = params_error} =
               Instruction.new(target: BasicAction, params: ["not", "keyword"])

      refute Jido.Action.Error.retryable?(params_error)
      assert params_error.details.params == ["not", "keyword"]
      assert byte_size(params_error.details.expected_format) > 0

      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               Instruction.new(target: BasicAction, context: ["not", "keyword"])

      assert {:error, %Jido.Action.Error.InvalidInputError{message: params_message}} =
               Instruction.new(target: BasicAction, params: 123)

      assert params_message =~ "Invalid params format"

      assert {:error, %Jido.Action.Error.InvalidInputError{message: context_message}} =
               Instruction.new(target: BasicAction, context: 123)

      assert context_message =~ "Invalid context format"

      assert {:error, %Jido.Action.Error.InvalidInputError{message: metadata_message}} =
               Instruction.new(target: BasicAction, metadata: 123)

      assert metadata_message =~ "Invalid metadata format"
    end

    test "does not accept tuple instruction shims" do
      assert {:error, %Jido.Action.Error.InvalidInputError{details: details}} =
               Instruction.new({BasicAction, %{value: 1}})

      assert details.reason == :invalid_attributes
    end

    test "returns a validation error for malformed list attributes" do
      assert {:error, %Jido.Action.Error.InvalidInputError{message: message}} =
               Instruction.new([:not_keyword])

      assert message == "Invalid instruction configuration"
    end
  end

  describe "normalize!/3" do
    @describetag obligation: ["jido_action.instruction.I4", "jido_action.instruction.I3"]

    for field <- [:params, :context, :metadata] do
      @field field
      test "rejects false #{@field} in a raw Instruction" do
        attrs = %{@field => false, target: Add}
        assert {:error, %Jido.Action.Error.InvalidInputError{} = error} = Instruction.new(attrs)
        assert error.details[@field] == false

        assert_raise Jido.Action.Error.InvalidInputError, error.message, fn ->
          Instruction.new!(attrs)
        end

        instruction = struct!(Instruction, attrs)

        assert_raise Jido.Action.Error.InvalidInputError,
                     ~r/Invalid #{to_string(@field)}/i,
                     fn -> Instruction.normalize!(instruction, %{override: 1}, %{override: 2}) end
      end
    end

    test "normalizes nil raw fields and preserves false values inside maps" do
      instruction = %Instruction{target: Add, params: nil, context: nil, metadata: nil}
      normalized = Instruction.normalize!(instruction, %{enabled: false}, %{enabled: false})
      assert normalized.params == %{enabled: false}
      assert normalized.context == %{enabled: false}
      assert normalized.metadata == %{}
    end

    test "uses shallow call-site overrides and preserves caller metadata" do
      metadata = %{timeout: 0, task_supervisor: :description_only, nested: %{id: "one"}}

      base =
        Instruction.new!(
          target: Add,
          params: %{nested: %{old: true}, keep: 1},
          context: %{nested: %{old: true}, keep: 2},
          metadata: metadata
        )

      normalized = Instruction.normalize!(base, [nested: %{new: true}], nested: nil)

      assert normalized.params == %{nested: %{new: true}, keep: 1}
      assert normalized.context == %{nested: nil, keep: 2}
      assert normalized.metadata === metadata
    end

    test "builds an instruction from an action module" do
      instruction = Instruction.normalize!(Add, [amount: 2], trace_id: "trace")

      assert %Instruction{target: Add, params: %{amount: 2}, context: %{trace_id: "trace"}} =
               instruction
    end

    test "builds from an instruction and merges call-site overrides" do
      base =
        Instruction.new!(
          target: Add,
          params: %{amount: 1, value: 5},
          context: %{trace_id: "base"}
        )

      instruction =
        Instruction.normalize!(
          base,
          %{amount: 3},
          %{tenant_id: "tenant"}
        )

      assert instruction.target == Add
      assert instruction.params == %{amount: 3, value: 5}
      assert instruction.context == %{trace_id: "base", tenant_id: "tenant"}
      assert instruction.metadata == %{}
    end

    test "keeps nested metadata when it normalizes an instruction" do
      metadata = %{
        request: %{id: "req-1", source: %{name: "api"}},
        tags: ["flow", "priority"]
      }

      base =
        Instruction.new!(
          target: MathFlow.flow(),
          params: %{value: 1},
          context: %{trace_id: "base"},
          metadata: metadata
        )

      instruction = Instruction.normalize!(base, %{value: 2}, %{tenant: "acme"})

      assert instruction.target === base.target
      assert instruction.params == %{value: 2}
      assert instruction.context == %{trace_id: "base", tenant: "acme"}
      assert instruction.metadata === metadata
    end

    test "builds from a runtime Flow target" do
      flow = MathFlow.flow()
      instruction = Instruction.normalize!(flow, %{value: 2}, %{tenant: "acme"})

      assert instruction.target === flow
      assert instruction.params == %{value: 2}
      assert instruction.context == %{tenant: "acme"}
      assert instruction.metadata == %{}
    end

    test "normalizes nil params and context" do
      instruction = Instruction.normalize!(Add, nil, nil)

      assert instruction.params == %{}
      assert instruction.context == %{}
    end

    test "rejects invalid normalization inputs" do
      assert_raise Jido.Action.Error.ConfigurationError, ~r/unknown Instruction target/, fn ->
        Instruction.normalize!(nil)
      end

      invalid = %Instruction{target: "not executable"}

      assert_raise Jido.Action.Error.ConfigurationError,
                   ~r/unknown Instruction target/,
                   fn -> Instruction.normalize!(invalid) end

      assert_raise ArgumentError, ~r/expected params to be a map or keyword list/, fn ->
        apply(Instruction, :normalize!, [Add, 123])
      end

      assert_raise ArgumentError, ~r/expected a map or keyword list/, fn ->
        Instruction.normalize!(Add, [:not, :keyword])
      end

      assert_raise ArgumentError, ~r/expected context to be a map or keyword list/, fn ->
        apply(Instruction, :normalize!, [Add, %{}, 123])
      end
    end
  end

  describe "new!/1" do
    @describetag obligation: "jido_action.instruction.I3"

    test "returns the instruction on success" do
      instruction = Instruction.new!(target: BasicAction, params: %{value: 7})
      assert instruction.target == BasicAction
      assert instruction.params == %{value: 7}
      assert instruction.metadata == %{}
    end

    test "raises on invalid input" do
      assert_raise Jido.Action.Error.InvalidInputError, fn ->
        Instruction.new!(params: %{value: 1})
      end
    end

    test "raises underlying exception errors" do
      assert_raise Jido.Action.Error.InvalidInputError, ~r/Invalid params format/, fn ->
        Instruction.new!(target: BasicAction, params: 123)
      end
    end
  end
end
