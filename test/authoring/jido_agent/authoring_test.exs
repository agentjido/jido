Code.require_file("../support/jido_agent/composable_compiler.exs", __DIR__)

defmodule Jido.Agent.Authoring.AuthoringTest do
  use ExUnit.Case, async: true
  @moduletag :authoring
  alias Jido.Agent
  alias Jido.Test.Agent.Authoring.Compiler

  test "Map and DSL definitions initialize the same complete state with static Joi schemas" do
    cases = [
      {"Jido.Joi.object(%{name: Jido.Joi.string()})", Jido.Joi.object(%{name: Jido.Joi.string()}), %{name: "Ada"},
       %{name: "Ada"}},
      {"Jido.Joi.object(%{enabled: Jido.Joi.boolean() |> Jido.Joi.default(false), amount: Jido.Joi.integer() |> Jido.Joi.default(0), note: Jido.Joi.string() |> Jido.Joi.nullable() |> Jido.Joi.default(nil)})",
       Jido.Joi.object(%{
         enabled: Jido.Joi.boolean() |> Jido.Joi.default(false),
         amount: Jido.Joi.integer() |> Jido.Joi.default(0),
         note: Jido.Joi.string() |> Jido.Joi.nullable() |> Jido.Joi.default(nil)
       }), %{}, %{enabled: false, amount: 0, note: nil}},
      {"Jido.Joi.object(%{profile: Jido.Joi.object(%{name: Jido.Joi.string()})})",
       Jido.Joi.object(%{profile: Jido.Joi.object(%{name: Jido.Joi.string()})}), %{profile: %{name: "Ada"}},
       %{profile: %{name: "Ada"}}},
      {"Jido.Joi.object(%{items: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})",
       Jido.Joi.object(%{items: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])}), %{}, %{items: []}}
    ]

    for {source, schema, supplied, expected} <- cases do
      module = Compiler.compile("state do schema #{source} end")
      from_map = Agent.define!(%{module: module, name: "generated", schema: schema})
      assert module.definition() === from_map
      assert Map.from_struct(module.definition()) === Map.from_struct(from_map)

      for definition <- [module.definition(), from_map] do
        instance = Agent.instantiate!(definition, id: "one", state: supplied)
        assert instance.state === expected
        assert Agent.definition(instance) === definition
        assert {:ok, ^instance} = Agent.validate(instance)

        assert {:error, _} =
                 Agent.instantiate(definition,
                   id: "bad",
                   state: Map.put(supplied, :unknown, true)
                 )
      end
    end
  end

  test "partial identity and state combinations are invalid" do
    definition = Agent.define!(%{name: "boundary"})

    for value <- [
          %{definition | id: "one"},
          %{definition | state: %{}},
          %{definition | id: "", state: %{}}
        ] do
      assert {:error, _} = Agent.validate(value)
      refute Agent.definition?(value)
      refute Agent.instance?(value)
    end

    assert {:ok, ^definition} = Agent.define(%{name: "boundary", id: nil, state: nil})

    for attrs <- [%{id: "one"}, %{state: %{}}] do
      assert {:error, _} = Agent.define(Map.merge(%{name: "boundary"}, attrs))
    end
  end

  test "stored state validation cannot insert missing defaults" do
    definition =
      Agent.define!(%{
        name: "strict",
        schema: Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
      })

    assert {:error, _} = Agent.validate(%{definition | id: "one", state: %{}})
    assert {:error, _} = Agent.instantiate(definition, id: "one", state: %{count: "2"})

    assert {:ok, %{state: %{count: 0}}} =
             Agent.instantiate(definition, id: "one", state: %{count: nil})

    assert {:ok, %{state: %{count: 0}}} = Agent.instantiate(definition, id: "one")
  end
end
