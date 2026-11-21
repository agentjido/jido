defmodule Jido.Examples.Applications.BehaviorTree.Agent do
  @moduledoc "Resumes a tree and applies its Action results and Directives."

  alias Jido.BehaviorTree.Tree
  alias Jido.BehaviorTree.Nodes.{Action, Sequence, SetBlackboard, Wait}
  alias Jido.Examples.Applications.BehaviorTree.Reserve
  alias Jido.Joi

  use Jido.Agent,
    name: "reservation_tree",
    plugins: [
      {Jido.Plugin.BehaviorTree,
       %{
         tree:
           Tree.new(
             Sequence.new([
               SetBlackboard.new(:stage, :started),
               Wait.new(0),
               Action.new(Reserve, %{quantity: {:from_blackboard, :quantity}})
             ])
           ),
         blackboard: %{quantity: 3}
       }}
    ]

  state do
    schema Joi.object(%{reserved: Joi.integer() |> Joi.default(0)})
  end

  routes do
    signal_source "/examples/11/07/reservation"
  end
end

defmodule Jido.Examples.Applications.BehaviorTree.Reserve do
  @moduledoc "Adds the requested quantity and asks Jido to emit a Signal after commit."

  alias Jido.Agent.Directive
  alias Jido.Joi

  use Jido.Action,
    name: "reserve_stock",
    schema: Joi.object(%{quantity: Joi.integer() |> Joi.min(1)})

  @impl true
  def run(%{quantity: quantity}, %{agent_state: %{reserved: reserved}}) do
    total = reserved + quantity
    {:ok, %{reserved: total}, [Directive.emit("examples.11.07.stock.reserved", %{reserved: total})]}
  end
end
