Code.require_file("errors_and_output_validation.ex", __DIR__)

defmodule Jido.Examples.Actions.ErrorsAndOutputValidationTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Actions.ErrorsAndOutputValidation.CheckShipment

  test "keeps execution errors distinct from output validation errors" do
    assert {:error, %Jido.Error.ExecutionError{}} =
             Jido.Exec.run(CheckShipment, %{weight_kg: 2}, %{mode: :reject})

    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.Exec.run(CheckShipment, %{weight_kg: 2}, %{mode: :invalid_output})

    assert {:ok, %{status: :accepted}} = Jido.Exec.run(CheckShipment, %{weight_kg: 2})
  end
end
