defmodule Jido.Agent.StateTest do
  use ExUnit.Case, async: true

  alias Jido.Agent

  def observe(value, _opts) do
    send(self(), {:validated, value})
    :ok
  end

  test "initialization validates unchanged state once" do
    schema =
      Zoi.object(%{
        count: Zoi.integer() |> Zoi.refine({__MODULE__, :observe, []}) |> Zoi.default(0)
      })

    definition = Agent.new!(name: "single_validation", schema: schema)

    for overrides <- [[], [state: %{count: 4}]] do
      assert {:ok, agent} = Agent.instantiate(definition, overrides)
      assert_received {:validated, value}
      assert value == agent.state.count
      refute_received {:validated, _}
    end
  end

  test "defaults and explicit nil cannot insert invalid values" do
    for schema <- [
          Zoi.object(%{count: Zoi.integer() |> Zoi.default("invalid")}),
          Zoi.object(%{nested: Zoi.object(%{count: Zoi.integer() |> Zoi.default("invalid")})})
        ],
        state <- [%{}, %{count: nil}, %{nested: %{}}] do
      definition = Agent.new!(name: "invalid_default", schema: schema)
      assert {:error, %Jido.Error.ValidationError{}} = Agent.instantiate(definition, state: state)
    end
  end

  test "initialization retains nested defaults, explicit nil, and supplied values" do
    schema =
      Zoi.object(%{
        config: Zoi.map() |> Zoi.default(%{first: 1, second: 2}),
        count: Zoi.integer() |> Zoi.default(3),
        optional: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil)
      })

    definition = Agent.new!(name: "nested_defaults", schema: schema)

    assert {:ok, agent} =
             Agent.instantiate(definition, state: %{config: %{second: 4}, count: nil})

    assert agent.state == %{config: %{first: 1, second: 4}, count: 3, optional: nil}

    assert {:error, %Jido.Error.ValidationError{details: %{missing_keys: [:config, :count]}}} =
             Agent.transition(agent, %{optional: nil})
  end
end
