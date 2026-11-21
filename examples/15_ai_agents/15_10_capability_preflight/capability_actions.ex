defmodule Jido.Examples.AI.CapabilityPreflight.Check do
  @moduledoc "Validates requirements against application-owned model metadata."

  use Jido.Action,
    name: "examples_ai_capability_preflight_check",
    schema:
      Jido.Joi.object(%{
        model: Jido.Joi.string() |> Jido.Joi.min(1),
        profile: Jido.Joi.map(),
        required: Jido.Joi.list(Jido.Joi.atom())
      })

  @impl true
  def run(input, _context) do
    missing = Enum.reject(input.required, &enabled?(input.profile, &1))

    if missing == [] do
      {:ok, %{checked: input.required, model: input.model}}
    else
      {:error,
       Jido.Error.validation_error("model capability preflight failed",
         details: %{missing: missing, model: input.model}
       )}
    end
  end

  defp enabled?(profile, capability) do
    Map.get(profile, capability, Map.get(profile, Atom.to_string(capability), false)) == true
  end
end

defmodule Jido.Examples.AI.CapabilityPreflight.Generate do
  @moduledoc "Calls the selected inference client after preflight succeeds."

  use Jido.Action,
    name: "examples_ai_capability_preflight_generate",
    schema:
      Jido.Joi.object(%{
        checked: Jido.Joi.list(Jido.Joi.atom()),
        model: Jido.Joi.string(),
        prompt: Jido.Joi.string()
      })

  @impl true
  def run(input, context) do
    client = Jido.AI.InferenceClient.Selection.client!(context)
    prompt = ReqLLM.Context.new([ReqLLM.Context.user(input.prompt)])

    with {:ok, response} <-
           client.generate_text(input.model, prompt, offline_response: "Capability preflight passed.") do
      {:ok,
       %{
         checked: input.checked,
         model: input.model,
         output: ReqLLM.Response.text(response)
       }}
    end
  end
end
