defmodule Jido.Examples.Guardrails.InputOutputPolicy.CheckInput do
  use Jido.Action,
    name: "example_guardrail_check_input",
    schema:
      Jido.Joi.object(%{
        input: Jido.Joi.string() |> Jido.Joi.min(1),
        failure_mode: Jido.Joi.enum([:fail_open, :fail_closed])
      })

  @impl true
  def run(%{input: input, failure_mode: failure_mode}, _context) do
    findings = findings(input)

    case {findings, failure_mode} do
      {[], _mode} ->
        {:ok, checked(input, findings, :passed)}

      {_findings, :fail_open} ->
        {:ok, checked(redact(input), findings, :continued_after_findings)}

      {_findings, :fail_closed} ->
        {:error,
         Jido.Error.validation_error("input policy rejected the request", %{
           boundary: :model_input,
           findings: findings
         })}
    end
  end

  defp findings(input) do
    []
    |> add_if(Regex.match?(~r/\b[^\s@]+@[^\s@]+\.[^\s@]+\b/, input), :pii_email)
    |> add_if(String.contains?(String.downcase(input), "ignore previous"), :prompt_injection)
    |> add_if(String.contains?(String.downcase(input), "build a bomb"), :moderation)
    |> Enum.reverse()
  end

  defp add_if(findings, true, finding), do: [finding | findings]
  defp add_if(findings, false, _finding), do: findings

  defp redact(input), do: Regex.replace(~r/\b[^\s@]+@[^\s@]+\.[^\s@]+\b/, input, "[EMAIL]")

  defp checked(input, findings, decision) do
    %{
      input: input,
      findings: findings,
      decision: decision,
      input_digest: Base.encode16(:crypto.hash(:sha256, input), case: :lower)
    }
  end
end

defmodule Jido.Examples.Guardrails.InputOutputPolicy.CallModel do
  use Jido.Action, name: "example_guardrail_call_model"

  @impl true
  def run(%{checked: checked}, context) do
    client = Jido.AI.InferenceClient.Selection.client!(context)
    prompt = ReqLLM.Context.new([ReqLLM.Context.user(checked.input)])
    options = [offline_response: Map.get(context, :offline_response, "Safe offline answer")]

    case client.generate_text("offline:guardrails", prompt, options) do
      {:ok, response} ->
        {:ok,
         %{
           text: ReqLLM.Response.text(response),
           model: response.model,
           input_check: checked
         }}

      {:error, reason} ->
        {:error, Jido.Error.execution_error("model request failed", %{reason: reason})}
    end
  end
end

defmodule Jido.Examples.Guardrails.InputOutputPolicy.CheckOutput do
  use Jido.Action, name: "example_guardrail_check_output"

  @impl true
  def run(%{model_result: %{text: text} = model_result}, _context) do
    if String.contains?(String.downcase(text), "private credential") do
      {:error,
       Jido.Error.validation_error("output policy rejected the response", %{
         boundary: :model_output,
         findings: [:credential_disclosure]
       })}
    else
      {:ok, Map.put(model_result, :output_check, %{decision: :passed, findings: []})}
    end
  end
end

defmodule Jido.Examples.Guardrails.InputOutputPolicy.RecordAudit do
  use Jido.Action, name: "example_guardrail_record_audit"

  @impl true
  def run(%{checked: checked}, context) do
    {:ok,
     %{
       output: checked.text,
       model: checked.model,
       audit: %{
         trace_id: Map.get(context, :trace_id, "offline-trace"),
         input_digest: checked.input_check.input_digest,
         input_decision: checked.input_check.decision,
         input_findings: checked.input_check.findings,
         output_decision: checked.output_check.decision,
         output_findings: checked.output_check.findings
       }
     }}
  end
end

defmodule Jido.Examples.Guardrails.InputOutputPolicy do
  use Jido.Flow,
    name: "example_guardrail_input_output_policy",
    schema:
      Jido.Joi.object(%{
        input: Jido.Joi.string() |> Jido.Joi.min(1),
        failure_mode: Jido.Joi.enum([:fail_open, :fail_closed])
      })

  alias Jido.Examples.Guardrails.InputOutputPolicy.{
    CallModel,
    CheckInput,
    CheckOutput,
    RecordAudit
  }

  flow do
    step "check_input",
      action: CheckInput,
      params: %{input: input(:input), failure_mode: input(:failure_mode)}

    step "call_model", action: CallModel, params: %{checked: result("check_input")}

    step "check_output",
      action: CheckOutput,
      params: %{model_result: result("call_model")}

    step "record_audit", action: RecordAudit, params: %{checked: result("check_output")}
    output result("record_audit")
  end
end
