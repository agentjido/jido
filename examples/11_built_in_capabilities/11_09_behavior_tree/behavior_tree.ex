defmodule Jido.Examples.Applications.BehaviorTree.Agent do
  @moduledoc "Defines a tree that reserves stock and emits a Signal after commit."

  use Jido.Agent, name: "reservation_tree"
  use Jido.BehaviorTree.DSL

  alias Jido.Agent.Directive
  alias Jido.BehaviorTree.Nodes.SetBlackboard
  alias Jido.Joi

  state do
    schema Joi.object(%{
             available_stock: Joi.integer() |> Joi.min(0) |> Joi.default(5),
             reserved: Joi.integer() |> Joi.default(0)
           })
  end

  behavior_tree :reservation, blackboard: %{requested_quantity: 3} do
    sequence :reserve_stock do
      node :mark_started, SetBlackboard.new(:stage, :started)
      wait :next_tick, milliseconds: 0
      condition :has_stock, state(:available_stock) >= blackboard(:requested_quantity)

      action :reserve,
             [quantity <- blackboard(:requested_quantity), available <- state(:available_stock)],
             inline: [
               schema: Joi.object(%{quantity: Joi.integer() |> Joi.min(1), available: Joi.integer()}),
               context: context
             ] do
        reserve(context.agent_state.reserved + quantity, available - quantity)
      end
    end
  end

  routes do
    signal_source "/examples/11/09/reservation"
  end

  defp reserve(total, available) do
    {:ok, %{reserved: total, available_stock: available},
     [Directive.emit("examples.11.09.stock.reserved", %{reserved: total})]}
  end
end
