defmodule Jido.Examples.Actions.InputOutputSchemas.NormalizeProfile do
  alias Jido.Joi

  use Jido.Action,
    name: "example_action_normalize_profile",
    schema:
      Joi.object(%{
        name: Joi.string() |> Joi.min(1),
        age: Joi.integer() |> Joi.min(0)
      }),
    output_schema:
      Joi.object(%{
        display_name: Joi.string() |> Joi.min(1),
        adult?: Joi.boolean()
      })

  @impl true
  def run(%{name: name, age: age}, _context) do
    {:ok, %{display_name: name |> String.trim() |> String.upcase(), adult?: age >= 18}}
  end
end
