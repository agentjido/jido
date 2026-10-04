defmodule Jido.Examples.DurableDelete do
  @moduledoc "A deleted order challenged by a delayed writer from its initial revision."
  use Jido.Agent, name: "examples_durable_delete"

  agent do
    schema Zoi.object(%{status: Zoi.string() |> Zoi.default("open")})
  end

  def delayed_write(store, order) do
    Jido.Persistence.save_agent(store, order,
      namespace: "durable-delete-example",
      revision: 1,
      expected_revision: 0
    )
  end
end
