defmodule Jido.Plugin.EctoStateTest do
  use Covenant.Case, component: "jido.plugin.ecto_state", async: true

  alias Jido.{Agent, Joi}
  alias Jido.Catalog.Discovery
  alias Jido.Plugin.EctoState

  defmodule Row do
    use Ecto.Schema

    schema "rows" do
      field(:lock_version, :integer, default: 1)
    end

    def repo, do: Jido.Test.Persistence.EctoRepo
    def changeset(row, attrs), do: Ecto.Changeset.cast(row, attrs, [])
  end

  defmodule RowAgent do
    use Jido.Agent, name: "ecto_row"

    state do
      ecto(Row)
    end
  end

  @tag obligation: "jido.plugin.ecto_state.I1"
  test "the declaration selects the bundled provider and excludes a Joi domain schema" do
    assert EctoState in Discovery.included_plugins()
    definition = RowAgent.definition()
    assert [%{provider: EctoState, data: %{schema: Row}}] = definition.plugins
    assert {:ok, ^definition} = Agent.define(Map.from_struct(definition))

    attrs = Map.from_struct(%{definition | schema: Joi.object(%{also_owned: Joi.integer()})})
    assert {:error, %Jido.Error.ValidationError{details: %{reason: :ecto_state_schema_conflict}}} = Agent.define(attrs)
  end
end
