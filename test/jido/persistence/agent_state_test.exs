defmodule Jido.Persistence.AgentStateTest do
  use ExUnit.Case, async: true

  alias Jido.Agent

  test "checkpoint restore rejects missing defaults and preserves nullable nil" do
    schema =
      Zoi.object(%{
        nested:
          Zoi.object(%{count: Zoi.integer() |> Zoi.nullable() |> Zoi.default(3)})
          |> Zoi.default(%{})
      })

    agent =
      Agent.define!(%{name: "restore_defaults", schema: schema})
      |> Agent.instantiate!(id: Jido.Signal.ID.generate!())

    assert {:ok, stored_nil} = Agent.transition(agent, %{nested: %{count: nil}})
    assert {:ok, checkpoint} = Jido.Persistence.snapshot(stored_nil)
    assert {:ok, ^stored_nil} = Jido.Persistence.restore(checkpoint)

    for state <- [%{}, %{nested: %{}}] do
      assert {:error, %{__exception__: true}} =
               Jido.Persistence.restore(%{checkpoint | agent: %{checkpoint.agent | state: state}})
    end
  end

  test "input empty values do not remove stored nullable nil" do
    schema =
      Zoi.object(%{count: Zoi.integer() |> Zoi.nullable() |> Zoi.default(nil)},
        empty_values: [nil]
      )

    agent =
      Agent.define!(%{name: "empty_nil", schema: schema})
      |> Agent.instantiate!(id: Jido.Signal.ID.generate!())

    assert agent.state === %{count: nil}
    assert Agent.validate(agent) === {:ok, agent}
    assert Agent.transition(agent, agent.state) === {:ok, agent}
    assert {:ok, checkpoint} = Jido.Persistence.snapshot(agent)
    assert {:ok, ^agent} = Jido.Persistence.restore(checkpoint)
  end
end
