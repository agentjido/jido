defmodule Jido.Examples.Actions.EffectsAsData.PrepareEmail do
  use Jido.Action,
    name: "example_action_prepare_email",
    schema:
      Jido.Joi.object(%{
        message_id: Jido.Joi.string() |> Jido.Joi.min(1),
        recipient: Jido.Joi.string() |> Jido.Joi.min(1)
      }),
    output_schema: Jido.Joi.object(%{status: Jido.Joi.enum([:prepared])})

  @impl true
  def run(%{message_id: id, recipient: recipient}, _context) do
    effect = %{kind: :deliver_email, message_id: id, recipient: recipient}
    {:ok, %{status: :prepared}, [effect]}
  end
end
