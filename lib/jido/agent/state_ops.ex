defmodule Jido.Agent.StateOps do
  @moduledoc """
  Centralized state operation application for strategies.

  Separates state operations (state mutations) from external directives.
  All strategies should use these helpers to ensure consistent behavior.

  ## State Operation Types

  - `StateOp.SetState` - Deep merge attributes into state
  - `StateOp.ReplaceState` - Replace state wholesale
  - `StateOp.DeleteKeys` - Remove top-level keys
  - `StateOp.SetPath` - Set value at nested path
  - `StateOp.DeletePath` - Delete value at nested path

  Any other struct is treated as an external directive and passed through.
  """

  alias Jido.Agent
  alias Jido.Agent.State
  alias Jido.Agent.StateOp

  @doc """
  Merges action result into agent state.

  Uses deep merge semantics. Raises a state-size validation error if the
  configured agent budget is exceeded.
  """
  @spec apply_result(Agent.t(), map()) :: Agent.t()
  def apply_result(%Agent{} = agent, result) when is_map(result) do
    new_state = State.merge(agent.state, result)
    Jido.Agent.StateBudget.replace!(agent, new_state)
  end

  @doc """
  Applies a list of state operations to the agent.

  State operations modify agent state. External directives are collected
  and returned for the runtime to process.

  Returns `{updated_agent, external_directives}`. Raises a state-size validation
  error if an operation exceeds the configured agent budget.
  """
  @spec apply_state_ops(Agent.t(), [struct()]) :: {Agent.t(), [struct()]}
  def apply_state_ops(%Agent{} = agent, effects) do
    {final_agent, reversed_directives} =
      Enum.reduce(effects, {agent, []}, fn
        %StateOp.SetState{attrs: attrs}, {a, directives} ->
          new_state = State.merge(a.state, attrs)
          {Jido.Agent.StateBudget.replace!(a, new_state), directives}

        %StateOp.ReplaceState{state: new_state}, {a, directives} ->
          {Jido.Agent.StateBudget.replace!(a, new_state), directives}

        %StateOp.DeleteKeys{keys: keys}, {a, directives} ->
          new_state = Map.drop(a.state, keys)
          {Jido.Agent.StateBudget.replace!(a, new_state), directives}

        %StateOp.SetPath{path: path, value: value}, {a, directives} ->
          new_state = deep_put_in(a.state, path, value)
          {Jido.Agent.StateBudget.replace!(a, new_state), directives}

        %StateOp.DeletePath{path: path}, {a, directives} ->
          {_, new_state} = pop_in(a.state, path)
          {Jido.Agent.StateBudget.replace!(a, new_state), directives}

        %_{} = directive, {a, directives} ->
          {a, [directive | directives]}
      end)

    {final_agent, Enum.reverse(reversed_directives)}
  end

  @doc """
  Helper to put a value at a nested path, creating intermediate maps if needed.
  """
  @spec deep_put_in(map(), [atom()], term()) :: map()
  def deep_put_in(map, [key], value) do
    Map.put(map, key, value)
  end

  def deep_put_in(map, [key | rest], value) do
    nested = Map.get(map, key, %{})
    Map.put(map, key, deep_put_in(nested, rest, value))
  end
end
