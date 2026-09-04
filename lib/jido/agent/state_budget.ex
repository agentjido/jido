defmodule Jido.Agent.StateBudget do
  @moduledoc """
  Enforces an optional byte budget for the complete agent state.

  The size is the external term size from `:erlang.external_size/1`. It is
  not the BEAM heap size. A `nil` limit disables the size calculation.
  """

  alias Jido.Agent
  alias Jido.Error

  @type result :: {:ok, Agent.t()} | {:error, Error.ValidationError.t()}

  @doc "Returns the effective state budget, including the agent module's limit."
  @spec limit(Agent.t()) :: non_neg_integer() | nil
  def limit(agent) do
    module = Map.get(agent, :agent_module)

    module_limit =
      if is_atom(module) and function_exported?(module, :max_state_size, 0),
        do: module.max_state_size(),
        else: nil

    case {Map.get(agent, :max_state_size), module_limit} do
      {nil, limit} -> limit
      {limit, nil} -> limit
      {left, right} -> min(left, right)
    end
  end

  @doc "Checks the full state and returns the agent or a structured error."
  @spec check(Agent.t()) :: result()
  def check(agent) do
    case limit(agent) do
      nil -> {:ok, agent}
      max when is_integer(max) and max >= 0 -> check_size(agent, max)
      _ -> {:error, budget_error("Invalid agent state size budget", %{})}
    end
  end

  defp check_size(agent, max) do
    size = :erlang.external_size(agent.state)

    if size <= max do
      {:ok, agent}
    else
      {:error,
       budget_error("Agent state exceeds its size budget", %{
         max_state_size: max,
         actual_state_size: size
       })}
    end
  end

  defp budget_error(message, details) do
    Error.validation_error(message, kind: :state_size, subject: :state, details: details)
  end

  @doc "Checks the state, raising a validation error if the budget is exceeded."
  @spec check!(Agent.t()) :: Agent.t()
  def check!(agent) do
    case check(agent) do
      {:ok, agent} -> agent
      {:error, error} -> raise error
    end
  end

  @doc "Checks a proposed replacement while retaining the previous budget."
  @spec transition(Agent.t(), Agent.t()) :: result()
  def transition(previous, %Agent{} = candidate) do
    candidate
    |> Map.put(:max_state_size, limit(previous))
    |> Map.put(:agent_module, previous.agent_module)
    |> check()
  end

  @doc false
  @spec check_for_module(Agent.t(), module()) :: result()
  def check_for_module(%Agent{} = agent, module) do
    check(%{agent | agent_module: module})
  end

  def check_for_module(agent, _module), do: check(agent)

  @doc "Replaces the state or returns a structured budget error."
  @spec replace(Agent.t(), map()) :: result()
  def replace(%Agent{} = agent, state), do: check(%{agent | state: state})

  @doc "Replaces the state, raising a validation error if the budget is exceeded."
  @spec replace!(Agent.t(), map()) :: Agent.t()
  def replace!(%Agent{} = agent, state), do: check!(%{agent | state: state})

  @doc false
  @spec command(Agent.t(), (Agent.t() -> Agent.cmd_result())) :: Agent.cmd_result()
  def command(original, fun) do
    try do
      {candidate, directives} = fun.(check!(original))

      case transition(original, candidate) do
        {:ok, candidate} -> {candidate, directives}
        {:error, error} -> reject_command(original, error)
      end
    rescue
      error in Error.ValidationError ->
        if error.kind == :state_size,
          do: reject_command(original, error),
          else: reraise(error, __STACKTRACE__)
    end
  end

  defp reject_command(original, error) do
    {original, [%Agent.Directive.Error{error: error, context: :state_size}]}
  end
end
