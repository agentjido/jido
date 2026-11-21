defmodule Jido.BehaviorTree.Expression do
  @moduledoc "A Behavior Tree expression with access to the current blackboard."

  alias Jido.BehaviorTree.{Blackboard, Tick}
  alias Jido.Expr

  defmodule Reference do
    @moduledoc false
    @enforce_keys [:key]
    defstruct [:key]
  end

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: term()}

  @doc false
  @spec parse!(Macro.t(), Macro.Env.t()) :: t()
  def parse!(ast, caller) do
    case Expr.parse_value(ast, leaf_parser: &parse_reference/1) do
      {:ok, value} -> %__MODULE__{value: value}
      {:error, error} -> Jido.Instruction.Config.compile_error!(caller, Exception.message(error))
    end
  end

  @doc "Evaluates the expression against the current Tick."
  @spec evaluate(t(), Tick.t()) :: {:ok, term()} | {:error, Exception.t()}
  def evaluate(%__MODULE__{value: value}, %Tick{blackboard: blackboard}) do
    Expr.evaluate_value(value,
      resolve: fn %Reference{key: key}, path ->
        case Map.fetch(Blackboard.to_map(blackboard), key) do
          {:ok, value} ->
            {:ok, value}

          :error ->
            Jido.Error.validation_result(:missing_blackboard_key, path, "Missing blackboard key #{inspect(key)}")
        end
      end
    )
  end

  defp parse_reference({:blackboard, _, [key]}) when is_atom(key) or is_binary(key) or is_integer(key),
    do: {:ok, %Reference{key: key}}

  defp parse_reference(_ast), do: :error
end
