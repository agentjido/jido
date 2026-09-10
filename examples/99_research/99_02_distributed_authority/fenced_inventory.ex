defmodule Jido.Examples.FencedInventory do
  @moduledoc "Checks external ownership before inventory work and fenced effects."
  use Jido.Agent, name: "research_fenced_inventory"

  agent do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
    plugin Jido.Examples.FencedInventory.Gate
  end

  routes do
    signal_source "/examples/research/fenced_inventory"

    route "examples.research.fenced_inventory.record" do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        authority = context.plugin_inputs[Jido.Examples.FencedInventory.Gate].runtime

        with :ok <-
               Jido.Examples.FencedInventory.Authority.effect(
                 authority.authority,
                 authority.token,
                 value
               ) do
          {:ok, %{context.agent_state | value: value}}
        end
      end

      define :record, args: [:value]
    end
  end
end
