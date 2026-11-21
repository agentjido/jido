defmodule Jido.Examples.Applications.BehaviorTree.Agent do
  @moduledoc "Defines a tree that reserves stock and emits a Signal after commit."

  use Jido.Agent, name: "reservation_tree"
  use Jido.BehaviorTree.DSL

  alias Jido.Agent.Directive
  alias Jido.BehaviorTree.Nodes.SetBlackboard
  alias Jido.Joi

  state do
    schema Joi.object(%{reserved: Joi.integer() |> Joi.default(0)})
  end

  behavior_tree :reservation, blackboard: %{quantity: 3} do
    sequence :reserve_stock do
      node :mark_started, SetBlackboard.new(:stage, :started)
      wait :next_tick, milliseconds: 0
      condition :has_stock, blackboard(:quantity) >= 1

      action :reserve,
             quantity <- blackboard(:quantity),
             inline: [schema: Joi.object(%{quantity: Joi.integer() |> Joi.min(1)}), context: context] do
        reserve(context.agent_state.reserved + quantity)
      end
    end
  end

  routes do
    signal_source "/examples/11/07/reservation"
  end

  defp reserve(total) do
    {:ok, %{reserved: total}, [Directive.emit("examples.11.07.stock.reserved", %{reserved: total})]}
  end
end
