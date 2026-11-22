defmodule Jido.Examples.AI.CapabilityPreflight do
  @moduledoc "Checks an application model profile before one offline model call."

  alias Jido.Joi

  use Jido.Flow,
    name: "examples_ai_capability_preflight",
    schema:
      Joi.object(%{
        model: Joi.string() |> Joi.min(1),
        profile: Joi.map(),
        prompt: Joi.string() |> Joi.min(1),
        required: Joi.list(Joi.enum([:text, :image_input, :structured_output, :tools]))
      }),
    output_schema:
      Joi.object(%{
        checked: Joi.list(Joi.atom()),
        model: Joi.string(),
        output: Joi.string()
      })

  flow do
    step "preflight",
      action: Jido.Examples.AI.CapabilityPreflight.Check,
      params: %{
        model: input(:model),
        profile: input(:profile),
        required: input(:required)
      }

    step "generate",
      action: Jido.Examples.AI.CapabilityPreflight.Generate,
      params: %{
        checked: result("preflight", :checked),
        model: result("preflight", :model),
        prompt: input(:prompt)
      }

    output result("generate")
  end
end
