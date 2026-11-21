Code.require_file("input_output_schemas.ex", __DIR__)

defmodule Jido.Examples.Actions.InputOutputSchemasTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Actions.InputOutputSchemas.NormalizeProfile

  test "validates input and output around one Action" do
    assert {:ok, %{display_name: "ADA", adult?: true}} =
             Jido.Exec.run(NormalizeProfile, %{name: " Ada ", age: 36})
  end

  test "returns a structured validation error before Action work" do
    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.Exec.run(NormalizeProfile, %{name: "Ada", age: -1})
  end
end
