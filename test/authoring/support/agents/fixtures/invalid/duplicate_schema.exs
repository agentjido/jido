defmodule JidoTest.Authoring.Agents.Fixtures.Invalid.DuplicateSchema do
  use Jido.Agent, name: "invalid_duplicate_schema", schema: Zoi.object(%{})

  agent do
    schema Zoi.object(%{count: Zoi.integer()})
  end
end
