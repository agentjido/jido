defmodule Jido.Agent.JoiRuntimeTest do
  use Covenant.Case, component: "jido.agent", async: true

  alias Jido.Agent

  @tag obligation: ["jido.agent.I8", "jido.agent.I9"]
  test "container defaults are checked during creation and never filled in stored state" do
    for container <- [
          Jido.Joi.list(Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(1)})),
          Jido.Joi.map(Jido.Joi.string(), Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(1)}))
        ] do
      input = if Jido.Joi.Schema.kind(container) == :array, do: [%{}], else: %{"item" => %{}}
      expected = if is_list(input), do: [%{count: 1}], else: %{"item" => %{count: 1}}
      definition = Agent.define!(%{name: "containers", schema: Jido.Joi.object(%{items: container})})

      assert {:ok, agent} = Agent.instantiate(definition, id: "one", state: %{items: input})
      assert agent.state == %{items: expected}
      assert Agent.validate(agent) == {:ok, agent}
      assert {:error, _} = Agent.transition(agent, %{items: input})
    end
  end

  @tag obligation: ["jido.agent.I8", "jido.agent.I9"]
  test "discriminated union defaults cannot bypass validation" do
    for default <- [1, "invalid"] do
      union =
        Jido.Joi.discriminated_union(:kind, [
          Jido.Joi.object(%{kind: Jido.Joi.literal(:count), count: Jido.Joi.integer() |> Jido.Joi.default(default)}),
          Jido.Joi.object(%{kind: Jido.Joi.literal(:text), text: Jido.Joi.string()})
        ])

      definition = Agent.define!(%{name: "union", schema: Jido.Joi.object(%{item: union})})
      result = Agent.instantiate(definition, id: "one", state: %{item: %{kind: :count}})

      if is_integer(default) do
        assert {:ok, agent} = result
        assert agent.state == %{item: %{kind: :count, count: 1}}
        assert {:error, _} = Agent.transition(agent, %{item: %{kind: :count}})
      else
        assert {:error, _} = result
      end
    end
  end

  @tag obligation: ["jido.agent.I8", "jido.agent.I9"]
  test "keyword defaults are checked with Hex Joi" do
    for default <- [1, "invalid"] do
      definition =
        Agent.define!(%{
          name: "keyword",
          schema:
            Jido.Joi.object(%{
              options: Jido.Joi.keyword(count: Jido.Joi.integer() |> Jido.Joi.default(default)) |> Jido.Joi.default([])
            })
        })

      result = Agent.instantiate(definition, id: "one")

      if is_integer(default) do
        assert {:ok, agent} = result
        assert agent.state == %{options: [count: 1]}
        assert {:error, _} = Agent.transition(agent, %{options: []})
      else
        assert {:error, _} = result
      end
    end
  end
end
