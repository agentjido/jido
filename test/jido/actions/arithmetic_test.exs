defmodule Jido.Actions.ArithmeticTest do
  use JidoTest.Case, async: true
  alias Jido.Actions.Arithmetic
  @moduletag :capture_log

  # Test for Add action
  describe "Add" do
    test "adds two numbers correctly" do
      assert {:ok, %{result: 5}} = Arithmetic.Add.run(%{value: 2, amount: 3}, %{})
      assert {:ok, %{result: -1}} = Arithmetic.Add.run(%{value: -3, amount: 2}, %{})
      assert {:ok, %{result: 0}} = Arithmetic.Add.run(%{value: 0, amount: 0}, %{})
    end

    test "works with floating point numbers" do
      assert {:ok, %{result: 5.5}} = Arithmetic.Add.run(%{value: 2.5, amount: 3.0}, %{})
    end
  end

  # Test for Subtract action
  describe "Subtract" do
    test "subtracts two numbers correctly" do
      assert {:ok, %{result: -1}} = Arithmetic.Subtract.run(%{value: 2, amount: 3}, %{})
      assert {:ok, %{result: -5}} = Arithmetic.Subtract.run(%{value: -3, amount: 2}, %{})
      assert {:ok, %{result: 0}} = Arithmetic.Subtract.run(%{value: 0, amount: 0}, %{})
    end

    test "works with floating point numbers" do
      assert {:ok, %{result: -0.5}} = Arithmetic.Subtract.run(%{value: 2.5, amount: 3.0}, %{})
    end
  end

  # Test for Multiply action
  describe "Multiply" do
    test "multiplies two numbers correctly" do
      assert {:ok, %{result: 6}} = Arithmetic.Multiply.run(%{value: 2, amount: 3}, %{})
      assert {:ok, %{result: -6}} = Arithmetic.Multiply.run(%{value: -3, amount: 2}, %{})
      assert {:ok, %{result: 0}} = Arithmetic.Multiply.run(%{value: 0, amount: 5}, %{})
    end

    test "works with floating point numbers" do
      assert {:ok, %{result: 7.5}} = Arithmetic.Multiply.run(%{value: 2.5, amount: 3.0}, %{})
    end
  end

  # Test for Divide action
  describe "Divide" do
    test "divides two numbers correctly" do
      assert {:ok, %{result: 2.0}} = Arithmetic.Divide.run(%{value: 6, amount: 3}, %{})
      assert {:ok, %{result: -1.5}} = Arithmetic.Divide.run(%{value: -3, amount: 2}, %{})
    end

    test "returns error when dividing by zero" do
      assert {:error, "Cannot divide by zero"} =
               Arithmetic.Divide.run(%{value: 5, amount: 0}, %{})
    end

    test "works with floating point numbers" do
      assert {:ok, %{result: 0.8333333333333334}} =
               Arithmetic.Divide.run(%{value: 2.5, amount: 3.0}, %{})
    end
  end

  # Test for Square action
  describe "Square" do
    test "squares a number correctly" do
      assert {:ok, %{result: 4}} = Arithmetic.Square.run(%{value: 2}, %{})
      assert {:ok, %{result: 9}} = Arithmetic.Square.run(%{value: -3}, %{})
      assert {:ok, %{result: 0}} = Arithmetic.Square.run(%{value: 0}, %{})
    end

    test "works with floating point numbers" do
      assert {:ok, %{result: 6.25}} = Arithmetic.Square.run(%{value: 2.5}, %{})
    end
  end
end
