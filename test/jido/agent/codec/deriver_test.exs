defmodule Jido.Agent.Codec.RegistryDerivationTest do
  use ExUnit.Case, async: true
  alias Jido.Agent
  alias Jido.Agent.Codec
  alias JidoTest.AgentFixtures.{Add, CounterAgent}

  test "derivation records all referenced kinds and keeps first occurrences" do
    definition =
      Agent.define!(%{
        name: "derived",
        module: CounterAgent,
        schema: Zoi.object(%{count: Zoi.integer()}),
        metadata: %{status: :ready, uri: %URI{host: "example.com"}},
        extensions: [
          %{
            id: Jido.Plugin.Scheduler.id(),
            provider: Jido.Plugin.Scheduler,
            vsn: 1,
            data: %{time_scale: SchedEx.IdentityTimeScale}
          }
        ],
        routes: [
          %{path: "counter.add", handler: %{kind: :action, target: Add}, defaults: %{by: 1}}
        ]
      })

    assert {:ok, _, registry} = Codec.encode(definition)
    values = Map.values(registry.entries)

    for kind <- [:agent, :schema, :atom, :value, :plugin, :action],
        do: assert(Enum.any?(values, &(elem(&1, 0) == kind)))

    assert Enum.count(values, &(&1 == {:atom, :status})) == 1
  end

  test "derivation rejects invalid handler data before creating a Registry" do
    definition =
      Agent.define!(%{
        name: "invalid",
        routes: [%{path: "valid", handler: %{kind: :action, target: Add}}]
      })

    [route] = definition.routes
    invalid = %{definition | routes: [%{route | handler: %{route.handler | target: 42}}, route]}
    assert {:error, %{path: [:routes, 0, :handler]}} = Codec.encode(invalid)
  end
end
