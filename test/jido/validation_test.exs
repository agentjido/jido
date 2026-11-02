defmodule Jido.ValidationTest do
  use ExUnit.Case, async: true

  alias Jido.Validation

  test "returns neutral validation errors" do
    assert {:error, %Validation.Error{} = error} =
             Validation.open_validate(Zoi.integer(), "bad", %{phase: :input})

    assert error.details.phase == :input
    assert error.__struct__ == Validation.Error
  end

  test "owns neutral schema shape checks" do
    assert Validation.zoi_schema?(Zoi.integer())
    assert Validation.map_schema?(Zoi.object(%{value: Zoi.integer()}))
    refute Validation.map_schema?(Zoi.integer())
  end
end
