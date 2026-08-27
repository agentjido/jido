defmodule JidoTest.SchemaTest do
  use ExUnit.Case, async: true

  alias Jido.Schema

  def valid_value(_value, _opts), do: :ok

  test "accepts a Zoi schema and the empty schema sentinel" do
    assert :ok = Schema.validate_config_schema(Zoi.object(%{name: Zoi.string()}))
    assert :ok = Schema.validate_config_schema([])
  end

  test "rejects NimbleOptions and JSON schemas" do
    assert {:error, "must be a Zoi schema"} =
             Schema.validate_config_schema(name: [type: :string])

    assert {:error, "must be a Zoi schema"} =
             Schema.validate_config_schema(%{"type" => "object", "properties" => %{}})
  end

  test "accepts static MFA schema effects" do
    schema = Zoi.string() |> Zoi.refine({__MODULE__, :valid_value, []})

    assert ^schema = Schema.ensure_static_schema!(schema, :schema, __ENV__)
  end

  test "rejects anonymous schema callbacks" do
    schema = Zoi.string() |> Zoi.refine(fn _value -> :ok end)

    assert_raise CompileError, ~r/anonymous functions are not supported/, fn ->
      Schema.ensure_static_schema!(schema, :schema, __ENV__)
    end
  end

  test "rejects lazy schemas" do
    schema = Zoi.lazy(fn -> Zoi.string() end)

    assert_raise CompileError, ~r/lazy schemas are not supported/, fn ->
      Schema.ensure_static_schema!(schema, :schema, __ENV__)
    end
  end
end
