defmodule Jido.Agent.AuthoringContractTest do
  use ExUnit.Case, async: true
  alias Jido.Agent
  alias Jido.Agent.Command
  alias Jido.AgentServer.Directive, as: Runtime
  alias JidoTest.AgentFixtures.Add

  defmodule Factory do
    def new, do: Agent.define!(%{name: "factory"})
  end

  test "Map authoring and instance options reject ambiguous duplicates" do
    assert {:error, %{code: :invalid_map}} = Agent.define(name: "first", name: "last")
    definition = Agent.define!(%{name: "state", schema: Zoi.object(%{count: Zoi.integer()})})
    assert {:error, %{code: :invalid_options}} = Agent.instantiate(definition, id: "a", id: "b")
    assert {:ok, %{key: 2}} = Command.normalize_context(key: 1, key: 2)
    assert {:ok, %{}} = Command.normalize_context(nil)
    instance = Agent.instantiate!(definition, id: "state", state: %{count: 0})
    assert {:ok, %{state: %{count: 2}}} = Agent.set(instance, count: 1, count: 2)

    for value <- [~D[2026-09-07], [:invalid], [key: 1] ++ [:invalid], [1 | :tail]] do
      assert {:error, _} = Command.normalize_context(value)
      assert {:error, _} = Agent.set(instance, value)
      assert {:error, _} = Agent.instantiate(definition, value)
    end
  end

  test "routes accept one module with separate plain Map defaults" do
    for defaults <- [%{}, %{by: 2}] do
      assert {:ok, definition} = Agent.define(%{name: "routes", routes: [route(Add, defaults)]})
      assert [%{handler: %{target: Add, kind: :action}, defaults: ^defaults}] = definition.routes
    end

    for target <- [[], [Add], {Add, %{}}] do
      assert {:error, _} = Agent.define(%{name: "routes", routes: [route(target, %{})]})
    end

    for defaults <- [nil, [], [by: 1], %URI{}] do
      assert {:error, %{path: [:routes, 0, :defaults]}} =
               Agent.define(%{name: "routes", routes: [route(Add, defaults)]})
    end
  end

  test "module provenance does not make a factory an Agent definition source" do
    assert {:error, _} = Runtime.validate_agent_target(Factory)
    assert {:error, %{code: :unresolved_definition}} = Agent.instantiate(Factory, id: "factory")
    assert {:ok, definition} = Agent.define(%{name: "origin", module: Factory})
    assert definition.module == Factory
  end

  test "portable definitions reject arbitrary values and obsolete Registry kinds" do
    definition =
      Agent.define!(%{
        name: "registry",
        metadata: %{a: [:repeat, %URI{port: 1}, :repeat, %URI{port: 1.0}], b: {:last, <<255>>}},
        routes: [route(Add, %{by: 1})]
      })

    assert {:error, %Jido.Authoring.Value.Error{reason: :value}} =
             Agent.Codec.encode(definition, JidoTest.AgentRegistry.for(definition))

    for entry <- [{:value, %URI{}}, {:route_match, &is_map/1}] do
      assert {:error, _error} = Jido.Agent.Codec.Registry.new(%{"obsolete" => entry})
    end
  end

  defp route(target, defaults),
    do: %{path: "counter.add", handler: %{kind: :action, target: target}, defaults: defaults}
end
