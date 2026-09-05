defmodule Jido.Agent.StateBudget do
  @moduledoc """
  Checks an optional byte limit for complete Agent state, including Plugin state.

  Size means `:erlang.external_size/1`, not BEAM heap size. A `nil` limit avoids
  the size calculation. The smaller of the definition and module limits applies.
  """

  alias Jido.Agent
  alias Jido.Error

  @doc "Checks a configured limit without measuring state."
  @spec validate_limit(term()) :: :ok | {:error, Error.ValidationError.t()}
  def validate_limit(nil), do: :ok
  def validate_limit(value) when is_integer(value) and value >= 0, do: :ok

  def validate_limit(_value),
    do: {:error, error("Invalid Agent state size budget", %{})}

  @doc "Returns the effective state limit."
  @spec limit(Agent.t()) :: non_neg_integer() | nil
  def limit(agent), do: smaller(Map.get(agent, :max_state_size), module_limit(agent))

  @doc "Checks the full state and returns the Agent or a structured error."
  @spec check(Agent.t()) :: {:ok, Agent.t()} | {:error, Error.ValidationError.t()}
  def check(agent) do
    with :ok <- validate_limit(Map.get(agent, :max_state_size)),
         :ok <- validate_limit(module_limit(agent)) do
      case limit(agent) do
        nil -> {:ok, agent}
        max -> check_size(agent, max)
      end
    end
  end

  @doc "Checks a replacement under the previous Agent's module and limit."
  @spec transition(Agent.t(), Agent.t()) :: {:ok, Agent.t()} | {:error, Error.ValidationError.t()}
  def transition(previous, candidate) do
    candidate
    |> Map.put(:module, previous.module)
    |> Map.put(:max_state_size, limit(previous))
    |> check()
  end

  defp module_limit(%{module: module}) do
    if is_atom(module) and function_exported?(module, :max_state_size, 0),
      do: module.max_state_size(),
      else: nil
  end

  defp smaller(nil, right), do: right
  defp smaller(left, nil), do: left
  defp smaller(left, right), do: min(left, right)

  defp check_size(agent, max) do
    actual = :erlang.external_size(agent.state)

    if actual <= max do
      {:ok, agent}
    else
      {:error,
       error("Agent state exceeds its size budget", %{
         max_state_size: max,
         actual_state_size: actual
       })}
    end
  end

  defp error(message, details),
    do: Error.validation_error(message, kind: :state_size, subject: :state, details: details)
end
