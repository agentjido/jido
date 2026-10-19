defmodule Jido.Agent.HexZoiTest do
  use ExUnit.Case, async: true

  alias Jido.Agent

  test "container defaults are checked during creation and never filled in stored state" do
    for container <- [
          Zoi.list(Zoi.object(%{count: Zoi.integer() |> Zoi.default(1)})),
          Zoi.map(Zoi.string(), Zoi.object(%{count: Zoi.integer() |> Zoi.default(1)}))
        ] do
      input = if match?(%Zoi.Types.Array{}, container), do: [%{}], else: %{"item" => %{}}
      expected = if is_list(input), do: [%{count: 1}], else: %{"item" => %{count: 1}}
      definition = Agent.define!(%{name: "containers", schema: Zoi.object(%{items: container})})

      assert {:ok, agent} = Agent.instantiate(definition, id: "one", state: %{items: input})
      assert agent.state == %{items: expected}
      assert Agent.validate(agent) == {:ok, agent}
      assert {:error, _} = Agent.transition(agent, %{items: input})
    end
  end

  test "discriminated union defaults cannot bypass validation" do
    for default <- [1, "invalid"] do
      union =
        Zoi.discriminated_union(:kind, [
          Zoi.object(%{kind: Zoi.literal(:count), count: Zoi.integer() |> Zoi.default(default)}),
          Zoi.object(%{kind: Zoi.literal(:text), text: Zoi.string()})
        ])

      definition = Agent.define!(%{name: "union", schema: Zoi.object(%{item: union})})
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

  test "keyword defaults are checked with Hex Zoi" do
    for default <- [1, "invalid"] do
      definition =
        Agent.define!(%{
          name: "keyword",
          schema:
            Zoi.object(%{
              options:
                Zoi.keyword(count: Zoi.integer() |> Zoi.default(default)) |> Zoi.default([])
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
