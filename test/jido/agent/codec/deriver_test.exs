defmodule Jido.Agent.Codec.DeriverTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Codec.Deriver
  alias JidoTest.AgentFixtures.Add

  test "agent derivation records first occurrences of all referenced kinds" do
    schema = Zoi.object(%{count: Zoi.integer()})

    definition =
      Agent.new!(
        name: "derived",
        schema: schema,
        metadata: %{status: :ready, uri: %URI{host: "example.com"}},
        plugins: [{Jido.Plugin.Scheduler, time_scale: SchedEx.IdentityTimeScale}],
        routes: [{"counter.add", {Add, %{by: 1}}, match: &String.trim/1}]
      )

    assert {:ok, registry} = Deriver.agent(definition)
    kinds = registry.entries |> Map.values() |> Enum.map(&elem(&1, 0))

    for kind <- [:agent, :schema, :atom, :value, :plugin, :action, :route_match] do
      assert kind in kinds
    end

    assert Enum.count(registry.entries, fn {_id, entry} -> entry == {:atom, :status} end) == 1
  end

  test "plugin derivation includes its module and static options" do
    assert {:ok, registry} =
             Deriver.plugin({Jido.Plugin.Scheduler, label: :primary, value: %URI{port: 443}})

    assert {:plugin, Jido.Plugin.Scheduler} in Map.values(registry.entries)
    assert {:atom, :label} in Map.values(registry.entries)
    assert {:atom, :primary} in Map.values(registry.entries)
    assert {:value, %URI{port: 443}} in Map.values(registry.entries)
  end

  test "agent derivation stops at the first invalid route" do
    definition = Agent.new!(name: "invalid_route", routes: [{"valid", Add}])
    [route] = definition.routes
    invalid = %{definition | routes: [%{route | target: 42}, route]}

    assert {:error, %Jido.Action.Error.ConfigurationError{}} = Deriver.agent(invalid)
  end
end
