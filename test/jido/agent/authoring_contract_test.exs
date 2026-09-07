defmodule Jido.Agent.AuthoringContractTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.{Builder, Command, Directive}
  alias JidoTest.AgentFixtures.Add

  defmodule Factory do
    def new, do: Agent.new!(name: "factory") |> Agent.instantiate!(id: "factory")
  end

  test "input normalization preserves each public boundary's duplicate policy" do
    assert {:ok, %{name: "last"} = definition} = Agent.new(name: "first", name: "last")
    assert {:ok, %{id: "last"}} = Agent.instantiate(definition, id: "first", id: "last")

    assert {:error, %{message: "Expected unique keyword options"}} =
             Builder.new(name: "first", name: "last") |> Builder.build()

    assert {:ok, %{key: 2}} = Command.normalize_context(key: 1, key: 2)
    assert {:ok, %{}} = Command.normalize_context(nil)

    agent = Agent.new!(name: "state", schema: Zoi.object(%{count: Zoi.integer()}))
    instance = Agent.instantiate!(agent, state: %{count: 0})
    assert {:ok, %{state: %{count: 2}}} = Agent.set(instance, count: 1, count: 2)

    for value <- [~D[2026-09-07], [:invalid], [key: 1] ++ [:invalid], [1 | :tail]] do
      assert {:error, %{details: %{context: ^value}}} = Command.normalize_context(value)
      assert {:error, %{details: %{attrs: ^value}}} = Agent.set(instance, value)
      assert {:error, %{details: %{value: ^value}}} = Agent.instantiate(agent, value)
    end
  end

  test "route splitting preserves tuples, plain targets, and explicit defaults validation" do
    for defaults <- [%{}, %{by: 2}, %URI{port: 1}] do
      target = {Add, defaults}

      assert {:ok, %{routes: [%{target: ^target}]}} =
               Agent.new(name: "routes", routes: [{"counter.add", target}])

      assert {:ok, %{routes: [%{target: ^target}]}} =
               Builder.new(name: "routes")
               |> Builder.route("counter.add", target)
               |> Builder.build()
    end

    assert {:error, %{message: "Route defaults must be a plain map"}} =
             Builder.new(name: "routes")
             |> Builder.route("counter.add", Add, defaults: %URI{port: 1})
             |> Builder.build()

    assert {:ok, %{routes: [%{target: Add}]}} =
             Agent.new(name: "routes", routes: [{"counter.add", Add}])

    assert {:error, %{message: "Invalid Agent route executable"}} =
             Agent.new(name: "routes", routes: [{"counter.add", {Add, nil}}])
  end

  test "constructor modules and behavior modules have separate contracts" do
    assert {:ok, %{agent: %{module: Agent, id: "factory"}}} =
             Jido.AgentServer.Options.new(agent: Factory)

    assert :ok = Directive.validate_agent_target(Factory)
    assert {:error, %{message: "Expected an Agent module"}} = Agent.new(Factory, [])

    assert {:error, %{message: "Expected an Agent module"}} =
             Builder.new(Factory) |> Builder.build()

    assert {:error, %{message: "Agent module must implement handle_signal/2"}} =
             Agent.new(name: "behavior", module: Factory)
  end
end
