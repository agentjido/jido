defmodule JidoActionTest.ActionTest do
  use Covenant.Case, component: "jido_action.action", async: true
  import JidoActionTest.Case
  @moduletag obligation: "jido_action.action.I1"

  alias Jido.Action
  alias Jido.Codec.Config
  alias Jido.Action.Output
  alias JidoActionTest.Fixtures.Actions.FullAction
  alias JidoActionTest.Fixtures.Actions.NoOutputSchemaAction
  alias JidoActionTest.Fixtures.Actions.NoSchema
  alias JidoActionTest.Fixtures.Actions.OutputSchemaAction

  describe "action creation and metadata" do
    test "creates a valid action with retained metadata" do
      assert FullAction.name() == "full_action"
      assert FullAction.description() == "A full action for testing"
      assert {:ok, fields} = Jido.Joi.Schema.fields(FullAction.schema())
      assert Jido.Joi.Schema.kind(FullAction.schema()) == :map
      assert fields |> field_keys() |> Enum.sort() == [:a, :b]
    end

    test "creates a valid action with default schemas" do
      assert NoSchema.name() == "add_two"
      assert NoSchema.description() == "Adds 2 to the input value"
      assert Jido.Joi.Schema.kind(NoSchema.schema()) == :map
      assert Jido.Joi.Schema.kind(NoSchema.output_schema()) == :map
    end

    test "exposes a JSON-safe Action description" do
      description = OutputSchemaAction.authoring_contract()

      assert Jason.decode!(Jason.encode!(description)) == description

      assert %{
               "kind" => "action",
               "name" => "output_schema_action",
               "description" => "Action that validates output with schema",
               "input_schema" => %{
                 "type" => "object",
                 "properties" => %{"input" => %{"type" => "string"}}
               },
               "output_schema" => %{
                 "type" => "object",
                 "properties" => %{
                   "length" => %{"type" => "integer"},
                   "result" => %{"type" => "string"}
                 }
               }
             } = description

      assert %{
               "input_schema" => %{"type" => "object"},
               "output_schema" => %{"type" => "object"}
             } = NoSchema.authoring_contract()
    end

    test "reports an Action schema without a JSON Schema representation" do
      module = unique_module("PidSchemaAction")

      create_module(
        module,
        quote do
          use Jido.Action,
            name: "pid_schema_action",
            schema: Jido.Joi.object(%{process: Jido.Joi.pid()})

          @impl true
          def run(params, _context), do: {:ok, params}
        end
      )

      assert_raise ArgumentError,
                   ~r/:schema does not have a JSON-safe JSON Schema representation/,
                   fn -> module.authoring_contract() end
    end

    test "rejects Action metadata that is not valid JSON" do
      module = unique_module("InvalidDescriptionAction")

      create_module(
        module,
        quote do
          use Jido.Action,
            name: "invalid_description_action",
            description: <<255>>

          @impl true
          def run(params, _context), do: {:ok, params}
        end
      )

      assert_raise ArgumentError, ~r/invalid_byte, 255/, fn -> module.authoring_contract() end
    end

    @tag obligation: "jido_action.action.I2"
    test "a missing run callback is reported during compilation" do
      module = unique_module("RuntimeDefaultAction")

      {_error, diagnostics} =
        Code.with_diagnostics(fn ->
          assert_raise CompileError, fn ->
            create_module(
              module,
              quote do
                use Jido.Action,
                  name: "runtime_default_action",
                  description: "Runtime default action"
              end
            )
          end
        end)

      assert Enum.any?(diagnostics, fn diagnostic ->
               diagnostic.message =~ "implementation not provided for predefined def run/2"
             end)
    end

    test "runtime compiled action supports non-literal options" do
      module = unique_module("RuntimeDynamicOptionsAction")
      schema = Jido.Joi.object(%{value: Jido.Joi.integer()})
      output_schema = Jido.Joi.object(%{doubled: Jido.Joi.integer()})

      create_module(
        module,
        quote do
          opts = [
            name: "runtime_dynamic_options_action",
            schema: unquote(Macro.escape(schema)),
            output_schema: unquote(Macro.escape(output_schema))
          ]

          use Jido.Action, opts

          @impl true
          def run(%{value: value}, _context), do: {:ok, %{doubled: value * 2}}
        end
      )

      assert module.name() == "runtime_dynamic_options_action"

      assert {:ok, %{value: 3}} = module.validate_params(%{value: 3, extra: "removed"})

      assert {:ok, %{doubled: 6}} = module.validate_output(%{doubled: 6, extra: "removed"})

      assert {:ok, %{doubled: 6}} = module.run(%{value: 3}, %{})
    end

    test "runtime compiled action supports nested schema variables" do
      module = unique_module("RuntimeSchemaVariableAction")

      create_module(
        module,
        quote do
          input_type = Jido.Joi.integer()
          output_type = Jido.Joi.string()

          use Jido.Action,
            name: "runtime_schema_variable_action",
            schema: Jido.Joi.object(%{value: input_type}),
            output_schema: Jido.Joi.object(%{result: output_type})

          @impl true
          def run(params, _context), do: {:ok, params}
        end
      )

      assert {:ok, %{value: 3}} = module.validate_params(%{value: 3})
      assert {:ok, %{result: "ok"}} = module.validate_output(%{result: "ok"})
    end

    @tag obligation: "jido_action.action.I2"
    test "supports static schemas with named MFA effects" do
      module = unique_module("StaticMfaSchemaAction")

      create_module(
        module,
        quote do
          use Jido.Action,
            name: "static_mfa_schema_action",
            schema:
              Jido.Joi.object(%{
                value:
                  Jido.Joi.integer()
                  |> Jido.Joi.refine({JidoActionTest.ActionTest, :at_least, [2]})
              }),
            output_schema:
              Jido.Joi.object(%{
                result:
                  Jido.Joi.integer()
                  |> Jido.Joi.refine({JidoActionTest.ActionTest, :at_least, [4]})
              })

          @impl true
          def run(params, _context), do: {:ok, params}
        end
      )

      assert {:ok, %{value: 2}} = module.validate_params(%{value: 2})

      assert {:error, %Jido.Error.ValidationError{}} =
               module.validate_params(%{value: 1})

      assert {:ok, %{result: 4}} = module.validate_output(%{result: 4})

      assert {:error, %Jido.Error.ValidationError{}} =
               module.validate_output(%{result: 3})
    end

    @tag obligation: "jido_action.action.I2"
    test "rejects anonymous functions in Action schemas" do
      schema_ast =
        quote do
          Jido.Joi.object(%{
            value: Jido.Joi.integer() |> Jido.Joi.refine(fn _value -> :ok end)
          })
        end

      for option <- [:schema, :output_schema] do
        module = unique_module("AnonymousSchemaAction")
        opts_ast = [{:name, "anonymous_schema_action"}, {option, schema_ast}]

        assert_raise CompileError,
                     ~r/#{option} must be static module data.*named MFA/s,
                     fn ->
                       create_module(
                         module,
                         quote do
                           use Jido.Action, unquote(opts_ast)
                         end
                       )
                     end
      end
    end

    @tag obligation: "jido_action.action.I2"
    test "rejects lazy Action schemas" do
      module = unique_module("LazySchemaAction")

      assert_raise CompileError, ~r/:schema must be static module data.*lazy schemas/s, fn ->
        create_module(
          module,
          quote do
            use Jido.Action,
              name: "lazy_schema_action",
              schema: Jido.Joi.lazy({JidoActionTest.ActionTest, :static_lazy_schema, []})
          end
        )
      end
    end

    @tag obligation: "jido_action.action.I2"
    test "rejects the removed schema bindings options" do
      module = unique_module("RemovedSchemaBindingsAction")

      assert_raise CompileError, ~r/unrecognized key: schema_bindings/, fn ->
        create_module(
          module,
          quote do
            use Jido.Action,
              name: "removed_schema_bindings_action",
              schema_bindings: [],
              schema: Jido.Joi.object(%{value: Jido.Joi.integer()})
          end
        )
      end
    end

    @tag obligation: "jido_action.action.I2"
    test "evaluates a static schema builder once" do
      module = unique_module("CountedStaticSchemaAction")
      counter = start_supervised!({Agent, fn -> 0 end})

      create_module(
        module,
        quote do
          use Jido.Action,
            name: "counted_static_schema_action",
            schema: JidoActionTest.ActionTest.counted_static_schema(unquote(counter))

          @impl true
          def run(params, _context), do: {:ok, params}
        end
      )

      assert Agent.get(counter, & &1) == 1
      assert {:ok, %{value: 1}} = module.validate_params(%{value: 1})
      assert module.schema() == module.schema()
      assert module.authoring_contract() == module.authoring_contract()
      assert Agent.get(counter, & &1) == 1
    end

    @tag obligation: "jido_action.action.I2"
    test "evaluates non-literal options once" do
      module = unique_module("CountedDynamicOptionsAction")
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      create_module(
        module,
        quote do
          use Jido.Action, JidoActionTest.ActionTest.counted_options(unquote(counter))

          @impl true
          def run(params, _context), do: {:ok, params}
        end
      )

      assert Agent.get(counter, & &1) == 1
      assert module.name() == "counted_dynamic_options_action"
    end

    @tag obligation: "jido_action.action.I2"
    test "invalid action configuration raises at compile time" do
      module = unique_module("InvalidActionConfig")

      assert_raise CompileError, ~r/Action configuration validation failed/, fn ->
        Code.compile_string("""
        defmodule #{inspect(module)} do
          use Jido.Action,
            name: "   "
        end
        """)
      end
    end

    @tag obligation: "jido_action.action.I2"
    test "unknown action options raise at compile time" do
      module = unique_module("UnknownActionOption")

      assert_raise CompileError, ~r/unrecognized key: output_shema/, fn ->
        Code.compile_string("""
        defmodule #{inspect(module)} do
          use Jido.Action,
            name: "unknown_action_option",
            output_shema: Jido.Joi.object(%{value: Jido.Joi.integer()})
        end
        """)
      end
    end
  end

  describe "configuration schema validation" do
    @describetag obligation: "jido_action.action.I2"
    test "validates non-blank string action names" do
      assert :ok = Config.validate_name("valid_name")
      assert :ok = Config.validate_name("ValidName")
      assert :ok = Config.validate_name("a")
      assert :ok = Config.validate_name("A")
      assert :ok = Config.validate_name(String.duplicate("a", 256))
      assert :ok = Config.validate_name(String.duplicate("é", 128))
    end

    test "validates action names with external or display-oriented punctuation" do
      assert :ok = Config.validate_name("valid_name_123")
      assert :ok = Config.validate_name("TestAction42")
      assert :ok = Config.validate_name("billing.charge-card")
      assert :ok = Config.validate_name("Send Email")
      assert :ok = Config.validate_name("checkout/v2")
    end

    test "rejects invalid action names" do
      assert {:error, "Action name cannot be blank."} = Config.validate_name("")
      assert {:error, "Action name cannot be blank."} = Config.validate_name(" \t\n")
      assert {:error, "Action name must be valid UTF-8."} = Config.validate_name(<<255>>)

      assert {:error, "Action name cannot exceed 256 bytes."} =
               Config.validate_name(String.duplicate("a", 257))

      assert {:error, "Action name must be a string."} = Config.validate_name(nil)
      assert {:error, "Action name must be a string."} = Config.validate_name(123)
      assert {:error, "Action name must be a string."} = Config.validate_name(:atom)
      assert {:error, "Action name must be a string."} = Config.validate_name(%{})
      assert {:error, "Action name must be a string."} = Config.validate_name([])
    end

    test "accepts Joi schemas and rejects empty lists" do
      assert :ok = Config.validate_config_schema(Jido.Joi.object(%{value: Jido.Joi.integer()}))
      assert {:error, "must be a Joi schema"} = Config.validate_config_schema([])
    end

    test "rejects non-Joi schemas" do
      assert {:error, "must be a Joi schema"} = Config.validate_config_schema(%{})
    end

    test "rejects schemas that cannot accept map-shaped data" do
      assert {:error, "must accept map-shaped data"} =
               Config.validate_map_schema(Jido.Joi.integer())

      assert {:error, "must accept map-shaped data"} =
               Config.validate_map_schema(Jido.Joi.lazy(fn -> Jido.Joi.integer() end))

      assert :ok =
               Config.validate_map_schema(Jido.Joi.lazy(fn -> Jido.Joi.object(%{value: Jido.Joi.integer()}) end))

      module = unique_module("ScalarOutputSchemaAction")

      assert_raise CompileError, ~r/must accept map-shaped data/, fn ->
        create_module(
          module,
          quote do
            use Jido.Action,
              name: "scalar_output_schema_action",
              output_schema: Jido.Joi.integer()
          end
        )
      end
    end

    test "rejects scalar results from flexible action schemas" do
      module = unique_module("ScalarTransformAction")

      create_module(
        module,
        quote do
          use Jido.Action,
            name: "scalar_transform_action",
            schema:
              Jido.Joi.object(%{})
              |> Jido.Joi.transform({JidoActionTest.ActionTest, :invalid_transform, []}),
            output_schema:
              Jido.Joi.object(%{})
              |> Jido.Joi.transform({JidoActionTest.ActionTest, :invalid_transform, []})

          @impl true
          def run(params, _context), do: {:ok, params}
        end
      )

      assert {:error,
              %Jido.Error.ValidationError{
                message: params_message,
                details: params_details
              }} =
               module.validate_params(%{})

      assert params_message == "Action validation must return a map"
      assert params_details == %{context: "Action", module: module, value: :invalid}

      assert {:error,
              %Jido.Error.ValidationError{
                message: output_message,
                details: output_details
              }} =
               module.validate_output(%{})

      assert output_message == "Action output validation must return a map"
      assert output_details == %{context: "Action output", module: module, value: :invalid}
    end
  end

  describe "static data validation" do
    @describetag obligation: "jido_action.action.I2"

    test "rejects nested runtime process values" do
      port = Port.open({:spawn_executable, System.find_executable("cat")}, [:binary])

      try do
        for value <- [self(), make_ref(), port] do
          assert {:error,
                  %Jido.Codec.Error.InvalidError{
                    code: :non_static_data,
                    message: "runtime process values are not supported at [:values, 1]"
                  }} = Config.validate_static_data(%{values: [:static, value]})
        end
      after
        Port.close(port)
      end
    end

    test "reports the exact paths of map keys, tuple values and improper-list heads" do
      function = fn -> :ok end

      cases = [
        {%{function => :value}, "anonymous functions are not supported at [:key]"},
        {{:static, function}, "anonymous functions are not supported at [1]"},
        {[:static, function], "anonymous functions are not supported at [1]"},
        {[:static, function | :tail], "anonymous functions are not supported at [1]"}
      ]

      for {value, message} <- cases do
        assert {:error,
                %Jido.Codec.Error.InvalidError{
                  code: :non_static_data,
                  message: ^message
                }} = Config.validate_static_data(value)
      end
    end

    test "rejects runtime process values from computed Action schemas" do
      module = unique_module("RuntimeValueSchemaAction")

      assert_raise CompileError, ~r/runtime process values are not supported/, fn ->
        create_module(
          module,
          quote do
            use Jido.Action,
              name: "runtime_value_schema_action",
              schema: Jido.Joi.object(%{value: Jido.Joi.any() |> Jido.Joi.default(self())})
          end
        )
      end
    end

    test "rejects lazy schemas before their builders run" do
      module = unique_module("ObservedLazySchemaAction")
      parent = self()

      assert_raise CompileError, ~r/lazy schemas are not supported/, fn ->
        create_module(
          module,
          quote do
            use Jido.Action,
              name: "observed_lazy_schema_action",
              schema: Jido.Joi.lazy({JidoActionTest.ActionTest, :observed_lazy_schema, [unquote(parent)]})
          end
        )
      end

      refute_received :lazy_schema_was_resolved
    end

    test "rejects improper list tails at their paths" do
      assert {:error,
              %Jido.Codec.Error.InvalidError{
                code: :non_static_data,
                message: "improper list tails are not supported at [1]"
              }} = Config.validate_static_data([:schema | :tail])

      assert {:error,
              %Jido.Codec.Error.InvalidError{
                code: :non_static_data,
                message: "improper list tails are not supported at [:schema, :steps, 1]"
              }} = Config.validate_static_data(%{schema: %{steps: [:step | :tail]}})
    end
  end

  describe "parameter validation" do
    @describetag obligation: "jido_action.action.I1"
    test "prepares raw parameters before schema validation" do
      module = unique_module("PrepareParamsAction")

      create_module(
        module,
        quote do
          use Jido.Action,
            name: "prepare_params_action",
            schema: Jido.Joi.object(%{enabled: Jido.Joi.boolean()}),
            output_schema: Jido.Joi.object(%{enabled: Jido.Joi.boolean()})

          @impl true
          def on_before_validate_params(%{"enabled" => value} = params)
              when value in ["true", "false"] do
            prepared =
              params
              |> Map.delete("enabled")
              |> Map.put(:enabled, value == "true")

            {:ok, prepared}
          end

          @impl true
          def run(params, _context), do: {:ok, params}
        end
      )

      assert {:ok, %{enabled: true}} = module.validate_params(%{"enabled" => "true"})
      assert {:ok, %{enabled: false}} = Jido.Exec.run(module, %{"enabled" => "false"})
    end

    test "returns an input preparation error without schema validation" do
      module = unique_module("RejectPreparedParamsAction")

      create_module(
        module,
        quote do
          use Jido.Action,
            name: "reject_prepared_params_action",
            schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

          @impl true
          def on_before_validate_params(_params), do: {:error, :unsafe_input}

          @impl true
          def run(params, _context), do: {:ok, params}
        end
      )

      assert {:error, :unsafe_input} = module.validate_params(%{value: "not an integer"})
    end

    test "validates required parameters" do
      assert {:error, %Jido.Error.ValidationError{message: message}} =
               FullAction.validate_params(%{})

      assert message =~ "required"
      assert message =~ "a"
    end

    test "validates parameter types" do
      assert {:error, %Jido.Error.ValidationError{message: message}} =
               FullAction.validate_params(%{a: "not an integer", b: 2})

      assert message =~ "expected integer"
    end

    test "uses the declared unknown-key policy" do
      assert {:ok, params} = FullAction.validate_params(%{a: 1, b: 2, trace_id: "trace-1"})
      assert params == %{a: 1, b: 2}
    end

    test "honors an explicit Joi unknown-key policy" do
      module = unique_module("StrictParamsAction")

      create_module(
        module,
        quote do
          use Jido.Action,
            name: "strict_params_action",
            schema: Jido.Joi.object(%{value: Jido.Joi.integer()}, unrecognized_keys: :error)

          @impl true
          def run(params, _context), do: {:ok, params}
        end
      )

      assert {:error, %Jido.Error.ValidationError{message: message}} =
               module.validate_params(%{extra: true, value: 1})

      assert message =~ "unrecognized key: extra"
    end

    test "supports struct schemas when validating params" do
      params_module = unique_module("StructParams")
      action_module = unique_module("StructSchemaAction")

      create_module(
        params_module,
        quote do
          defstruct [:value]
        end
      )

      schema = Jido.Joi.struct(params_module, [value: Jido.Joi.integer()], coerce: true)

      create_module(
        action_module,
        quote do
          use Jido.Action,
            name: "struct_schema_action",
            schema: unquote(Macro.escape(schema))

          @impl true
          def run(params, _context), do: {:ok, params}
        end
      )

      assert {:ok, %{value: 42}} =
               action_module.validate_params(%{value: 42, extra: "kept"})
    end

    test "returns validation error for unsupported schema types" do
      module = unique_module("UnsupportedSchemaAction")

      create_module(
        module,
        quote do
          def schema, do: :not_a_schema
        end
      )

      assert {:error, %Jido.Error.ValidationError{message: message, details: details}} =
               Action.validate_params_for(%{value: 1}, module)

      assert message == "Unsupported schema type"
      assert details.context == "Action"
      assert details.module == module
    end

    test "returns validation error for non-object Joi schemas" do
      module = unique_module("ScalarSchemaAction")

      create_module(
        module,
        quote do
          def schema, do: Jido.Joi.integer()
        end
      )

      assert {:error, %Jido.Error.ValidationError{message: message, details: details}} =
               Action.validate_params_for(%{value: 1}, module)

      assert message =~ "expected integer"
      assert [%{path: [], code: :invalid_type}] = details.errors
    end
  end

  describe "action execution" do
    test "executes a valid action successfully" do
      assert {:ok, result} = FullAction.run(%{a: 5, b: 2}, %{})
      assert result.a == 5
      assert result.b == 2
      assert result.result == 7
    end
  end

  describe "output validation" do
    @describetag obligation: "jido_action.action.I1"
    test "action with valid output schema validates successfully" do
      assert {:ok, result} =
               OutputSchemaAction.validate_output(%{result: "test", length: 4, extra: "data"})

      assert result.result == "test"
      assert result.length == 4
      refute Map.has_key?(result, :extra)
    end

    test "action with invalid output fails validation" do
      assert {:error, %Jido.Error.ValidationError{message: message, details: details}} =
               OutputSchemaAction.validate_output(%{result: "test"})

      assert message =~ "required"
      assert message =~ "length"
      assert details.context == "Action output"
      assert details.module == OutputSchemaAction
    end

    test "action without output schema skips validation" do
      assert {:ok, result} = NoOutputSchemaAction.validate_output(%{anything: "goes"})
      assert result.anything == "goes"
    end

    test "action output validation rejects malformed output envelopes" do
      output = %Output{kind: :batch, value: :not_a_list, meta: %{}}

      assert {:error, %Jido.Error.ValidationError{}} =
               NoOutputSchemaAction.validate_output(output)
    end
  end

  defp field_keys(fields), do: fields |> Map.new() |> Map.keys()

  def counted_options(counter) do
    Agent.update(counter, &(&1 + 1))
    [name: "counted_dynamic_options_action"]
  end

  def counted_static_schema(counter) do
    Agent.update(counter, &(&1 + 1))
    Jido.Joi.object(%{value: Jido.Joi.integer()})
  end

  def at_least(value, minimum, _opts) do
    if value >= minimum, do: :ok, else: {:error, "must be at least #{minimum}"}
  end

  def invalid_transform(_value, _opts), do: :invalid

  def static_lazy_schema, do: Jido.Joi.object(%{value: Jido.Joi.integer()})

  def observed_lazy_schema(parent) do
    send(parent, :lazy_schema_was_resolved)
    Jido.Joi.object(%{value: Jido.Joi.integer()})
  end
end
