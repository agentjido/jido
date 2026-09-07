defmodule JidoTest.PluginTestAction do
  @moduledoc false
  use Jido.Action,
    name: "plugin_test_action",
    schema: []

  def run(_params, _context), do: {:ok, %{}}
end

defmodule JidoTest.PluginTestAnotherAction do
  @moduledoc false
  use Jido.Action,
    name: "plugin_test_another_action",
    schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})

  def run(%{value: value}, _context), do: {:ok, %{value: value}}
end

defmodule JidoTest.NotAnActionModule do
  @moduledoc false
  def some_function, do: :ok
end

defmodule JidoTest.TestActions do
  @moduledoc """
  Shared test actions for Jido test suite.
  """

  alias Jido.Action

  defmodule BasicAction do
    @moduledoc false
    use Action,
      name: "basic_action",
      description: "A basic action for testing",
      schema: Zoi.object(%{value: Zoi.integer()})

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
