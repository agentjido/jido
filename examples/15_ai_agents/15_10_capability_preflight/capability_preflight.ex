defmodule Jido.Examples.AI.CapabilityPreflight do
  @moduledoc "Checks an application model profile before one offline model call."

  use Jido.Flow,
    name: "examples_ai_capability_preflight",
    schema:
      Jido.Joi.object(%{
        model: Jido.Joi.string() |> Jido.Joi.min(1),
        profile: Jido.Joi.map(),
        prompt: Jido.Joi.string() |> Jido.Joi.min(1),
        required: Jido.Joi.list(Jido.Joi.enum([:text, :image_input, :structured_output, :tools]))
      }),
    output_schema:
      Jido.Joi.object(%{
        checked: Jido.Joi.list(Jido.Joi.atom()),
        model: Jido.Joi.string(),
        output: Jido.Joi.string()
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
