Code.require_file("action_context.ex", __DIR__)

defmodule Jido.Examples.Actions.ActionContextTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Actions.ActionContext.CalculateQuote

  test "reads runtime policy from execution context" do
    assert {:ok, %{subtotal_cents: 10_000, tax_cents: 725, total_cents: 10_725}} =
             Jido.Exec.run(CalculateQuote, %{subtotal_cents: 10_000}, %{tax_basis_points: 725})
  end

  test "reports missing context as a structured error" do
    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.Exec.run(CalculateQuote, %{subtotal_cents: 10_000})
  end
end
