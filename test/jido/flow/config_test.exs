defmodule Jido.Flow.ConfigTest do
  use ExUnit.Case, async: true

  alias Jido.Flow.Config

  test "owns Flow configuration validation and Flow errors" do
    assert {:ok, %{name: "work", description: nil, schema: [], output_schema: []}} =
             Config.validate(%{name: "work"})

    assert {:error, error} = Config.validate(%{name: " ", extra: true})
    assert error.__struct__ == Jido.Flow.Error.InvalidDefinitionError
    assert error.details.key == :extra
  end

  test "validates one Flow schema field" do
    assert {:ok, []} = Config.schema(nil, "Flow schema")

    assert {:error, error} = Config.schema(:invalid, "Flow schema")
    assert error.details.field == "Flow schema"
  end
end
