defmodule Jido.BehaviorTree.Nodes.Condition do
  @moduledoc "Returns success for true and failure for false without changing the Tick."

  alias Jido.BehaviorTree.{Error, Expression}

  @behaviour Jido.BehaviorTree.Node
  @enforce_keys [:expression]
  defstruct [:expression]

  @doc "Creates a node that tests a Boolean expression."
  @spec new(Expression.t()) :: %__MODULE__{}
  def new(%Expression{} = expression), do: %__MODULE__{expression: expression}

  @impl true
  def tick(node, tick) do
    case Expression.evaluate(node.expression, tick) do
      {:ok, true} -> {:success, node}
      {:ok, false} -> {:failure, node}
      {:ok, _value} -> {{:error, Error.execution_error("Condition must return a Boolean")}, node}
      {:error, reason} -> {{:error, reason}, node}
    end
  end

  @impl true
  def halt(node), do: node
end
