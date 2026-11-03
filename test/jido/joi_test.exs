defmodule Jido.JoiTest do
  use ExUnit.Case, async: true

  alias Jido.Joi

  test "facade excludes Zoi functions outside the Jido contract" do
    refute function_exported?(Joi, :email, 0)
    refute function_exported?(Joi, :from_json_schema, 1)
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
end
