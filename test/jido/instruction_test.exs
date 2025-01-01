defmodule Jido.InstructionTest do
  use ExUnit.Case, async: true
  alias Jido.Instruction
  alias Jido.Error
  alias JidoTest.TestActions.BasicAction
  alias JidoTest.TestActions.NoSchema
  @moduletag :capture_log

  describe "normalize/2" do
    test "normalizes single instruction struct" do
      instruction = %Instruction{
        action: BasicAction,
        params: %{value: 1},
        context: %{local: true}
      }

      assert {:ok, [normalized]} = Instruction.normalize(instruction, %{request_id: "123"})
      assert normalized.action == BasicAction
      assert normalized.params == %{value: 1}
      assert normalized.context == %{local: true, request_id: "123"}
    end

    test "normalizes bare action module" do
      assert {:ok, [instruction]} = Instruction.normalize(BasicAction)

      assert instruction == %Instruction{
               action: BasicAction,
               params: %{},
               context: %{}
             }
    end

    test "normalizes action tuple with params" do
      assert {:ok, [instruction]} = Instruction.normalize({BasicAction, %{value: 42}})

      assert instruction == %Instruction{
               action: BasicAction,
               params: %{value: 42},
               context: %{}
             }
    end

    test "normalizes list of mixed formats" do
      input = [
        BasicAction,
        {NoSchema, %{data: "test"}},
        %Instruction{action: BasicAction, context: %{local: true}}
      ]

      assert {:ok, instructions} = Instruction.normalize(input, %{request_id: "123"})
      assert length(instructions) == 3

      [first, second, third] = instructions

      assert first == %Instruction{
               action: BasicAction,
               params: %{},
               context: %{request_id: "123"}
             }

      assert second == %Instruction{
               action: NoSchema,
               params: %{data: "test"},
               context: %{request_id: "123"}
             }

      assert third == %Instruction{
               action: BasicAction,
               params: %{},
               context: %{local: true, request_id: "123"}
             }
    end

    test "returns error for invalid params format" do
      assert {:error, %Error{}} = Instruction.normalize({BasicAction, "invalid"})
    end

    test "returns error for invalid instruction format" do
      assert {:error, %Error{}} = Instruction.normalize(123)
    end
  end

  describe "validate_allowed_actions/2" do
    test "returns ok when all actions are allowed" do
      instructions = [
        %Instruction{action: BasicAction},
        %Instruction{action: NoSchema}
      ]

      assert :ok = Instruction.validate_allowed_actions(instructions, [BasicAction, NoSchema])
    end

    test "returns error when actions are not allowed" do
      instructions = [
        %Instruction{action: BasicAction},
        %Instruction{action: UnregisteredAction}
      ]

      assert {:error, %Error{}} =
               Instruction.validate_allowed_actions(instructions, [BasicAction])
    end
  end
end
