defmodule Jido.JoiTest do
  use ExUnit.Case, async: true

  alias Jido.Joi

  test "facade covers the complete pinned dependency API" do
    assert Joi.facade_complete?()
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

  test "stored validation reports values that parsing would change" do
    schema = Joi.object(%{count: Joi.integer()}, unrecognized_keys: :strip)

    assert {:error, [error]} = Joi.validate(schema, %{count: 1, extra: true})
    assert Joi.Error.changed_value?(error)
  end

  test "initialization can add defaults but cannot convert supplied values" do
    schema = Joi.object(%{count: Joi.integer() |> Joi.transform(&(&1 + 1))})

    assert {:error, [error]} = Joi.initialize(schema, %{count: 1})
    assert Joi.Error.changed_value?(error)
  end

  test "parse bang raises the facade exception" do
    assert_raise Joi.ParseError, fn -> Joi.parse!(Joi.integer(), "one") end
  end
end
