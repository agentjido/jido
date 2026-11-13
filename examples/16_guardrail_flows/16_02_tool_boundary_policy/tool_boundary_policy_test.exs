Code.require_file("tool_boundary_policy.ex", __DIR__)

defmodule Jido.Examples.Guardrails.ToolBoundaryPolicyTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Guardrails.ToolBoundaryPolicy

  test "an allowed call and safe result cross both policy boundaries" do
    assert {:ok, result} =
             Jido.Exec.run(ToolBoundaryPolicy, %{
               tool: "lookup_policy",
               arguments: %{"topic" => "retention"}
             })

    assert result.safe_result.content == "Policy for retention: retain for 30 days"
    assert result.audit == %{call_decision: :allowed, result_decision: :passed}
  end

  test "a denied tool does not execute" do
    assert {:error, %Jido.Error.ValidationError{details: details}} =
             Jido.Exec.run(ToolBoundaryPolicy, %{
               tool: "delete_account",
               arguments: %{"topic" => "retention"}
             })

    assert details.boundary == :tool_call
    assert details.tool == "delete_account"
  end

  test "an unsafe tool result does not return to the model" do
    assert {:error, %Jido.Error.ValidationError{details: details}} =
             Jido.Exec.run(ToolBoundaryPolicy, %{
               tool: "lookup_policy",
               arguments: %{"topic" => "credentials"}
             })

    assert details.boundary == :tool_result
    assert details.findings == [:credential_disclosure]
  end
end
