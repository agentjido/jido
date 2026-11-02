defmodule Jido.Authoring.ConfigTest do
  use Covenant.Case, component: "jido_action.action", async: false

  alias Jido.Authoring.Config
  alias Jido.Flow.Error.InvalidDefinitionError

  def options do
    send(self(), :options_built)
    %{name: "counted", schema: schema(:input), output_schema: schema(:output)}
  end

  def schema(boundary) do
    send(self(), {:schema_built, boundary})
    Zoi.object(%{value: Zoi.integer() |> Zoi.default(1)})
  end

  @tag obligation: "jido_action.action.I1"
  test "Action and Flow default omitted and nil schemas to maps" do
    for kind <- [:action, :flow],
        options <- [
          "name: \"defaults\"",
          "%{name: \"defaults\", schema: nil, output_schema: nil}"
        ] do
      module = compile_module(kind, options)
      assert module.name() == "defaults"
      assert module.description() == nil
      assert %Zoi.Types.Map{} = module.schema()
      assert %Zoi.Types.Map{} = module.output_schema()
      assert %{"type" => "object"} = module.authoring_contract()["input_schema"]
      assert %{"type" => "object"} = module.authoring_contract()["output_schema"]
    end

    assert {:ok,
            %{
              name: "defaults",
              description: nil,
              schema: %Zoi.Types.Map{},
              output_schema: %Zoi.Types.Map{}
            }} =
             Config.validate_flow(%{name: "defaults", schema: nil, output_schema: nil})
  end

  @tag obligation: "jido_action.action.I1"
  test "Action and Flow expose stable authoring identity" do
    for kind <- [:action, :flow] do
      module = compile_module(kind, "id: \"tests/stable-id\", vsn: 3, name: \"stable\"")

      assert %{"id" => "tests/stable-id", "vsn" => 3} = module.authoring_contract()
      refute function_exported?(module, :authoring_id, 0)
      refute function_exported?(module, :authoring_vsn, 0)
      refute function_exported?(module, :to_json, 0)
    end
  end

  @tag obligation: "jido_action.action.I2"
  test "Action and Flow reject invalid authoring identity" do
    for kind <- [:action, :flow],
        options <- [
          "id: \"\", name: \"invalid\"",
          "id: \"bad id\", name: \"invalid\"",
          "id: :invalid, name: \"invalid\"",
          "vsn: 0, name: \"invalid\""
        ] do
      assert_raise CompileError, fn -> compile_module(kind, options) end
    end
  end

  @tag obligation: "jido_action.action.I2"
  test "module configuration errors keep messages, order, and declaration locations" do
    action_cases = [
      {"[]", "is required, at name"},
      {":invalid", "invalid type: expected map"},
      {"%{__struct__: __MODULE__, name: \"valid\"}", "invalid type: expected map"},
      {"name: :invalid", "invalid type: expected string, at name"},
      {"name: \"\"", "Action name cannot be blank., at name"},
      {"name: <<255>>", "Action name must be valid UTF-8., at name"},
      {"name: String.duplicate(\"a\", 257)", "Action name cannot exceed 256 bytes., at name"},
      {"name: \"valid\", description: nil", "invalid type: expected string, at description"},
      {"name: 2, description: 2, schema: 2, output_schema: 2, extra: true",
       "invalid type: expected string, at name\ninvalid type: expected string, at description\n" <>
         "must be a Zoi schema, at schema\nmust be a Zoi schema, at output_schema\n" <>
         "unrecognized key: extra"}
    ]

    flow_cases = [
      {"[]", "flow name must be a string"},
      {":invalid", "flow configuration must be a map"},
      {"name: :invalid", "flow name must be a string"},
      {"name: \"\"", "Action name cannot be blank."},
      {"name: <<255>>", "Action name must be valid UTF-8."},
      {"name: String.duplicate(\"a\", 257)", "Action name cannot exceed 256 bytes."},
      {"name: \"valid\", description: 2", "flow description must be a string"},
      {"name: \"valid\", description: <<255>>", "flow description must be valid UTF-8"},
      {"name: 2, schema: 2, extra: true", "unknown Flow configuration key: :extra"},
      {"name: 2, schema: 2", "flow name must be a string"}
    ]

    for {kind, cases, prefix} <- [
          {:action, action_cases, "Action configuration validation failed:\n"},
          {:flow, flow_cases, "Flow configuration validation failed: "}
        ],
        {options, message} <- cases do
      error = assert_raise CompileError, fn -> compile_module(kind, options) end
      assert error.description == prefix <> message
      assert error.file == "authoring_config_test.ex"
      assert error.line == 2
    end
  end

  @tag obligation: "jido_action.action.I2"
  test "schema failures keep boundary formatting and static errors take Action priority" do
    for field <- [:schema, :output_schema] do
      for {source, reason} <- [
            {"[]", "must be a Zoi schema"},
            {":invalid", "must be a Zoi schema"},
            {"Zoi.integer()", "must accept map-shaped data"},
            {"Zoi.object(%{value: Zoi.integer() |> Zoi.refine(fn _ -> :ok end)})",
             "must be static module data; anonymous functions are not supported at [:fields, 0, 1, :meta, :effects, 0, 1]"}
          ] do
        action_error =
          assert_raise CompileError, fn ->
            compile_module(:action, "name: \"valid\", #{field}: #{source}")
          end

        flow_error =
          assert_raise CompileError, fn ->
            compile_module(:flow, "name: \"valid\", #{field}: #{source}")
          end

        assert flow_error.description ==
                 "Flow configuration validation failed: #{field} #{reason}"

        if String.starts_with?(reason, "must be static") do
          assert action_error.description ==
                   ":#{field} #{reason}. Use named MFA effects such as {Module, :function, args}"
        else
          assert action_error.description ==
                   "Action configuration validation failed:\n#{reason}, at #{field}"
        end

        assert flow_error.line == 2
        assert action_error.line == 2
      end
    end

    error =
      assert_raise CompileError, fn ->
        compile_module(:action, "name: 2, extra: true, schema: fn -> :invalid end")
      end

    assert error.description =~ ":schema must be static module data; anonymous functions"
  end

  @tag obligation: "jido_action.action.I2"
  test "Flow data retains field details and nil descriptions" do
    assert {:ok, %{description: nil}} = Config.validate_flow(%{name: "valid", description: nil})

    assert {:error, %InvalidDefinitionError{message: "schema must be a Zoi schema", details: details}} =
             Config.validate_flow(%{name: "valid", schema: :invalid})

    assert details == %{field: "schema"}

    assert {:error, %InvalidDefinitionError{details: %{key: :extra}}} =
             Config.validate_flow(%{name: 2, extra: true})

    for {field, value} <- [name: nil, description: 2, schema: :invalid, output_schema: :invalid] do
      attrs = Map.put(%{name: "valid", components: [], output: %{}}, field, value)
      assert {:error, %InvalidDefinitionError{}} = Jido.Flow.new(attrs)
    end
  end

  @tag obligation: ["jido_action.action.I2", "jido_action.action.I1"]
  test "option and schema builders run once for both module forms and inline Actions" do
    for kind <- [:action, :flow] do
      module = compile_module(kind, "#{inspect(__MODULE__)}.options()")
      assert_received :options_built
      assert_received {:schema_built, :input}
      assert_received {:schema_built, :output}
      assert module.validate_params(%{}) == {:ok, %{value: 1}}
      assert module.validate_output(%{}) == {:ok, %{value: 1}}
      assert module.authoring_contract() == module.authoring_contract()
      refute_received :options_built
      refute_received {:schema_built, _}
    end

    owner = unique_module()
    cleanup(owner)

    Code.compile_string("""
    defmodule #{inspect(owner)} do
      use Jido.Flow, name: "inline"
      flow do
        step "work", value <- input(:value),
          inline: [schema: #{inspect(__MODULE__)}.schema(:input),
                   output_schema: #{inspect(__MODULE__)}.schema(:output)] do
          {:ok, %{value: value}}
        end
        output result("work")
      end
    end
    """)

    target = owner.step_action("work")
    cleanup(target)
    assert_received {:schema_built, :input}
    assert_received {:schema_built, :output}
    assert target.validate_params(%{}) == {:ok, %{value: 1}}
    assert target.__jido_authoring_kind__() == :action
    refute_received {:schema_built, _}
  end

  defp compile_module(kind, options) do
    module = unique_module()
    cleanup(module)

    {author, body} =
      case kind do
        :action ->
          {"Jido.Action", "@impl true\ndef run(params, _context), do: {:ok, params}"}

        :flow ->
          {"Jido.Flow",
           "flow do\nstep \"work\", action: JidoActionTest.Fixtures.Actions.Add, params: %{value: 1}\noutput %{}\nend"}
      end

    Code.compile_string(
      """
      defmodule #{inspect(module)} do
        use #{author}, #{options}
        #{body}
      end
      """,
      "authoring_config_test.ex"
    )

    module
  end

  defp unique_module,
    do: Module.concat(__MODULE__, "Module#{System.unique_integer([:positive])}")

  defp cleanup(module) do
    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
      :code.purge(module)
    end)
  end
end
