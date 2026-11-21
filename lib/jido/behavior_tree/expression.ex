defmodule Jido.BehaviorTree.Expression do
  @moduledoc "A Behavior Tree expression that can read the current blackboard and Agent state."

  alias Jido.BehaviorTree.{Blackboard, Tick}
  alias Jido.Expr

  defmodule Reference do
    @moduledoc false
    @enforce_keys [:key]
    defstruct [:key, source: :blackboard]
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
  def evaluate(%__MODULE__{value: value}, %Tick{} = tick) do
    Expr.evaluate_value(value, resolve: &resolve(&1, &2, tick))
  end

  defp resolve(%Reference{source: :state, key: key}, path, tick) do
    case Tick.agent_state(tick) do
      state when is_map(state) ->
        fetch(state, key, path, :missing_state_key, "Agent state")

      _ ->
        Jido.Error.validation_result(
          :missing_agent_state,
          path,
          "Agent state is unavailable for state(#{inspect(key)})"
        )
    end
  end

  defp resolve(%Reference{key: key}, path, tick) do
    fetch(Blackboard.to_map(tick.blackboard), key, path, :missing_blackboard_key, "blackboard")
  end

  defp fetch(values, key, path, code, label) do
    case Map.fetch(values, key) do
      {:ok, value} -> {:ok, value}
      :error -> Jido.Error.validation_result(code, path, "Missing #{label} key #{inspect(key)}")
    end
  end

  defp parse_reference({source, _, [key]})
       when source in [:blackboard, :state] and (is_atom(key) or is_binary(key) or is_integer(key)),
       do: {:ok, %Reference{source: source, key: key}}

  defp parse_reference(_ast), do: :error
end
