defmodule Jido.Examples.DefinitionRevision do
  @moduledoc "A saved definition retains its version and checks its executable references."

  defmodule Add do
    use Jido.Action, name: "definition_revision_add"
    def run(_input, %{agent_state: state}), do: {:ok, %{total: state.total + 1}}
  end

  defmodule Upgrade do
    @moduledoc "Explicitly selects the current Action for an older snapshot."
    use Jido.Action, name: "definition_revision_upgrade"

    def run(%{snapshot: snapshot}, _context) do
      agent = %{
        snapshot.agent
        | vsn: 2,
          routes: Jido.Examples.DefinitionRevision.definition().routes
      }

      with {:ok, saved} <- Jido.Persistence.snapshot(agent), do: {:ok, %{snapshot: saved}}
    end
  end

  use Jido.Agent, name: "examples_versioned_cart", vsn: 1

  agent do
    schema Zoi.object(%{total: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    route "examples.persistence.definition_revision.add", Add, as: :add
  end
end
