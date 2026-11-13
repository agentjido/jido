Code.require_file("testing_actions.ex", __DIR__)

defmodule Jido.Examples.Actions.TestingActionsTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Actions.TestingActions.ApplyDiscount

  test "checks representative successful cases through Exec" do
    for {percent, expected} <- [{0, 2_000}, {25, 1_500}, {100, 0}] do
      assert {:ok, %{total_cents: ^expected}} =
               Jido.Exec.run(ApplyDiscount, %{subtotal_cents: 2_000, discount_percent: percent})
    end
  end

  test "checks boundary failures without calling run/2 directly" do
    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.Exec.run(ApplyDiscount, %{subtotal_cents: 2_000, discount_percent: 101})
  end
end
