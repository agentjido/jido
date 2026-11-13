defmodule Jido.Examples.Guardrails.ToolBoundaryPolicy.CheckCall do
  use Jido.Action,
    name: "example_guardrail_check_tool_call",
    schema:
      Jido.Joi.object(%{
        tool: Jido.Joi.string() |> Jido.Joi.min(1),
        arguments: Jido.Joi.map()
      })

  @impl true
  def run(%{tool: "lookup_policy", arguments: %{"topic" => topic}}, _context)
      when is_binary(topic) and topic != "" do
    {:ok, %{tool: "lookup_policy", arguments: %{"topic" => topic}, decision: :allowed}}
  end

  def run(%{tool: tool}, _context) do
    {:error,
     Jido.Error.validation_error("tool call policy rejected the request", %{
       boundary: :tool_call,
       tool: tool,
       allowed_tools: ["lookup_policy"]
     })}
  end
end

defmodule Jido.Examples.Guardrails.ToolBoundaryPolicy.ExecuteLocalTool do
  use Jido.Action, name: "example_guardrail_execute_local_tool"

  @impl true
  def run(%{checked_call: %{arguments: %{"topic" => "credentials"}}}, _context) do
    {:ok, %{content: "private credential: offline-secret", source: "policy-fixture"}}
  end

  def run(%{checked_call: %{arguments: %{"topic" => topic}}}, _context) do
    {:ok, %{content: "Policy for #{topic}: retain for 30 days", source: "policy-fixture"}}
  end
end

defmodule Jido.Examples.Guardrails.ToolBoundaryPolicy.CheckResult do
  use Jido.Action, name: "example_guardrail_check_tool_result"

  @impl true
  def run(%{tool_result: %{content: content} = tool_result}, _context) do
    if String.contains?(content, "private credential") do
      {:error,
       Jido.Error.validation_error("tool result policy rejected the result", %{
         boundary: :tool_result,
         findings: [:credential_disclosure]
       })}
    else
      {:ok,
       %{
         safe_result: tool_result,
         audit: %{call_decision: :allowed, result_decision: :passed}
       }}
    end
  end
end

defmodule Jido.Examples.Guardrails.ToolBoundaryPolicy do
  use Jido.Flow,
    name: "example_guardrail_tool_boundary_policy",
    schema:
      Jido.Joi.object(%{
        tool: Jido.Joi.string() |> Jido.Joi.min(1),
        arguments: Jido.Joi.map()
      })

  alias Jido.Examples.Guardrails.ToolBoundaryPolicy.{CheckCall, CheckResult, ExecuteLocalTool}

  flow do
    step "check_call",
      action: CheckCall,
      params: %{tool: input(:tool), arguments: input(:arguments)}

    step "execute_tool",
      action: ExecuteLocalTool,
      params: %{checked_call: result("check_call")}

    step "check_result",
      action: CheckResult,
      params: %{tool_result: result("execute_tool")}

    output result("check_result")
  end
end
