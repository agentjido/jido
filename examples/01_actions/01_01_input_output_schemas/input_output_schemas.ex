defmodule Jido.Examples.Actions.InputOutputSchemas.NormalizeProfile do
  use Jido.Action,
    name: "example_action_normalize_profile",
    schema:
      Jido.Joi.object(%{
        name: Jido.Joi.string() |> Jido.Joi.min(1),
        age: Jido.Joi.integer() |> Jido.Joi.min(0)
      }),
    output_schema:
      Jido.Joi.object(%{
        display_name: Jido.Joi.string() |> Jido.Joi.min(1),
        adult?: Jido.Joi.boolean()
      })

  @impl true
  def run(%{name: name, age: age}, _context) do
    {:ok, %{display_name: name |> String.trim() |> String.upcase(), adult?: age >= 18}}
  end
end
