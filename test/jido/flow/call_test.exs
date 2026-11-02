defmodule Jido.Flow.CallTest do
  use ExUnit.Case, async: true

  alias Jido.Flow.{Call, Ref}
  alias Jido.Instruction
  alias JidoActionTest.Fixtures.Actions.BasicAction
  alias JidoActionTest.Fixtures.MathFlow

  test "normalizes compact, map, and string-key call data" do
    assert {:ok, %Call{} = compact} = Call.new({BasicAction, %{value: 1}})
    assert Call.target(compact) == BasicAction
    assert Call.canonical?(compact, :flow, "Step")

    assert {:ok, %Call{} = call} =
             Call.normalize(
               %{
                 "type" => "call",
                 "action" => BasicAction,
                 "params" => %{value: Ref.input(:value)},
                 "context" => %{tenant: Ref.context(:tenant)},
                 "metadata" => %{request: "one"},
                 "on_error" => :collect_errors
               },
               :flow,
               "Step"
             )

    assert call.on_error == :collect_errors
    assert Call.result_refs(call) == []
    assert Call.target(call) == BasicAction
    assert Call.with_on_error(call, :fail_fast).on_error == :fail_fast

    replacement = Instruction.new!(target: BasicAction, params: %{value: 2})
    assert Call.with_instruction(call, replacement).instruction == replacement
  end

  test "collects result references from parameters and context" do
    call =
      Call.new!(
        Instruction.new!(
          target: BasicAction,
          params: %{value: Ref.result(:load)},
          context: %{audit: Ref.result(:audit, :id)}
        )
      )

    assert Call.result_refs(call) == ["load", "audit"]
  end

  test "normalizes policy options for Action calls" do
    assert {:ok, %Call{} = call} =
             Call.from_options(
               BasicAction,
               %{value: 1},
               %{request: "one"},
               100,
               %{max_attempts: 2, delay_ms: 5},
               :collect_errors
             )

    assert call.policy == %{
             timeout_ms: 100,
             retry: %{max_attempts: 2, backoff: :fixed, base_delay_ms: 5, max_delay_ms: 5}
           }

    assert call.on_error == :collect_errors
  end

  test "rejects malformed call maps" do
    invalid = [
      %{"action" => BasicAction, action: BasicAction},
      %{action: BasicAction, unknown: true},
      %{type: :other, action: BasicAction},
      %{instruction: BasicAction, params: %{}},
      %{params: %{}},
      %{action: BasicAction, on_error: :other}
    ]

    for value <- invalid do
      assert {:error, %Jido.Flow.Error.InvalidDefinitionError{}} =
               Call.normalize(value, :flow, "Step")
    end

    refute Call.canonical?(%{}, :flow, "Step")
    assert_raise Jido.Flow.Error.InvalidDefinitionError, fn -> Call.new!(nil) end

    assert_raise FunctionClauseError, fn ->
      apply(Call, :with_on_error, [Call.new!(BasicAction), :other])
    end
  end

  test "permits call policy only for Action targets" do
    assert {:error, error} = Call.new({MathFlow, %{}}, %{timeout_ms: 100})
    assert error.details.reason == :unsupported_flow_call_policy

    unavailable = Module.concat(__MODULE__, "Unavailable")

    assert {:error,
            %Jido.Flow.Error.InvalidDefinitionError{details: %{cause: %Instruction.Error{}}}} =
             Call.new(unavailable, %{timeout_ms: 100})
  end
end
