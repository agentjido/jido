defmodule Jido.Examples.Actions.EffectsAsData.PrepareEmail do
  alias Jido.Joi

  use Jido.Action,
    name: "example_action_prepare_email",
    schema:
      Joi.object(%{
        message_id: Joi.string() |> Joi.min(1),
        recipient: Joi.string() |> Joi.min(1)
      }),
    output_schema: Joi.object(%{status: Joi.enum([:prepared])})

  @impl true
  def run(%{message_id: id, recipient: recipient}, _context) do
    effect = %{kind: :deliver_email, message_id: id, recipient: recipient}
    {:ok, %{status: :prepared}, [effect]}
  end
end
