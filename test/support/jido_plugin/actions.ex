defmodule Jido.Test.Plugin.Actions do
  @moduledoc """
  Shared test actions for Jido test suite.
  """

  alias Jido.Action

  defmodule BasicAction do
    @moduledoc false
    use Action,
      name: "basic_action",
      description: "A basic action for testing",
      schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

    def run(%{value: value}, _context) do
      {:ok, %{value: value}}
    end
  end

  defmodule NoSchema do
    @moduledoc false
    use Action,
      name: "no_schema",
      description: "Action with no schema"

    def run(%{value: value}, _context), do: {:ok, %{result: value + 2}}
    def run(_params, _context), do: {:ok, %{result: "No params"}}
  end
end
