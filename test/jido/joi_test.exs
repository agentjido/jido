defmodule Jido.JoiTest do
  use ExUnit.Case, async: true

  alias Jido.Joi

  test "facade excludes Zoi functions outside the Jido contract" do
    refute function_exported?(Joi, :email, 0)
    refute function_exported?(Joi, :from_json_schema, 1)

    for name <- [:base64, :base64url, :ipv4, :ipv6, :null], arity <- [0, 1] do
      refute function_exported?(Joi, name, arity)
    end
  end

  test "schemas stay interoperable across facade operations" do
    schema =
      Joi.object(%{
        count: Joi.integer() |> Joi.default(1),
        label: Joi.string()
      })

    assert {:ok, %{count: 1, label: "one"}} = Joi.initialize(schema, %{label: "one"})
    assert :ok = Joi.validate(schema, %{count: 1, label: "one"})
    assert {:error, [%{code: :required}]} = Joi.validate(schema, %{label: "one"})
  end

  test "open map validation preserves undeclared fields without validating them" do
    schema = Joi.object(%{count: Joi.integer()})
    input = %{count: 1, opaque: self()}

    assert {:ok, ^input} = Joi.parse(schema, input)
  end

  test "stored schemas reject key stripping" do
    schema = Joi.object(%{count: Joi.integer()}, unrecognized_keys: :strip)

    assert {:error, [error]} = Joi.validate(schema, %{count: 1, extra: true})
    assert Joi.error_code(error) == :joi_invalid_stored_schema
  end

  test "stored schemas reject transformations" do
    schema = Joi.object(%{count: Joi.integer() |> Joi.transform(&(&1 + 1))})

    assert {:error, [error]} = Joi.initialize(schema, %{count: 1})
    assert Joi.error_code(error) == :joi_invalid_stored_schema
  end

  test "stored validation reports refinements that change values" do
    schema = Joi.object(%{count: Joi.integer() |> Joi.refine({__MODULE__, :mutate, []})})

    assert {:error, [error]} = Joi.validate(schema, %{count: 1})
    assert Joi.changed_value?(error)
    assert Joi.error_code(error) == :joi_changed_value
    assert is_list(Joi.error_path(error))
    assert is_binary(Joi.error_message(error))
  end

  test "parse bang raises the facade exception" do
    assert_raise Joi.ParseError, fn -> Joi.parse!(Joi.integer(), "one") end
  end

  test "static validation rejects live values with exact paths" do
    assert Joi.validate_static(%{steps: [:one, self()]}) ==
             {:error, "runtime process values are not supported at [:steps, 1]"}

    assert Joi.validate_static([:one | :tail]) ==
             {:error, "improper list tails are not supported at [1]"}
  end

  test "static validation accepts named schema effects and rejects anonymous effects" do
    named = Joi.any() |> Joi.refine({__MODULE__, :accept, []})
    anonymous = Joi.any() |> Joi.refine(fn _value -> :ok end)

    assert :ok = Joi.validate_static(named)
    assert {:error, message} = Joi.validate_static(anonymous)
    assert message =~ "anonymous functions are not supported"
  end

  def accept(_value, _context), do: :ok

  def mutate(value, opts),
    do: %{opts[:ctx] | valid?: true, parsed: value + 1}

  describe "to_json_schema/1 required fields" do
    test "leaves out fields that validation fills from a default" do
      schema =
        Joi.object(%{
          id: Joi.string(),
          currency: Joi.string() |> Joi.default("usd"),
          flag: Joi.boolean() |> Joi.default(false),
          note: Joi.string() |> Joi.nullable() |> Joi.default(nil),
          kept: Joi.string() |> Joi.default("x") |> Joi.required()
        })

      json = Joi.to_json_schema(schema)

      assert json.required == [:id]
      assert json.properties.currency.default == "usd"

      assert {:ok, %{id: "a", currency: "usd", flag: false, note: nil, kept: "x"}} =
               Joi.parse(schema, %{id: "a"})
    end

    test "keeps a field whose default sits inside a nullable branch, as validation requires it" do
      schema = Joi.object(%{inner: Joi.nullable(Joi.default(Joi.string(), "a"))})

      assert Joi.to_json_schema(schema).required == [:inner]
      assert {:error, [%{code: :required}]} = Joi.parse(schema, %{})
    end

    test "applies to nested objects and treats a field named default as data" do
      nested = Joi.object(%{default: Joi.string(), city: Joi.string() |> Joi.default("x")})

      json =
        Joi.to_json_schema(
          Joi.object(%{
            one: nested,
            many: Joi.array(nested),
            maybe: Joi.nullable(nested)
          })
        )

      assert json.required |> Enum.sort() == [:many, :maybe, :one]
      assert json.properties.one.required == [:default]
      assert json.properties.many.items.required == [:default]
      assert [%{type: :null}, %{required: [:default]}] = json.properties.maybe.anyOf
    end
  end

  test "an Action authoring contract does not require a defaulted field" do
    defmodule DefaultedFieldAction do
      use Jido.Action,
        name: "defaulted_field_action",
        schema:
          Jido.Joi.object(%{
            order_id: Jido.Joi.string(),
            note: Jido.Joi.string() |> Jido.Joi.default("n")
          })

      @impl true
      def run(params, _context), do: {:ok, params}
    end

    assert DefaultedFieldAction.authoring_contract()["input_schema"]["required"] == ["order_id"]
  end
end
