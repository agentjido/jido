defmodule Jido.Agent.Strategy.State do
  @moduledoc """
  Helper module for managing strategy-specific state within an Agent.

  Strategy state is stored under the reserved key `:__strategy__` in `agent.state`.
  This keeps all state within the Agent struct for serializability and snapshot/restore.

  ## Structure

  The strategy state typically contains:
  - `:module` - The strategy module managing this state
  - `:status` - Current execution status (:idle, :running, :waiting, :success, :failure)
  - `:data` - Strategy-specific data (e.g., BT cursor, LLM conversation history)

  ## Example

      # In a Behavior Tree strategy
      agent = Strategy.State.put(agent, %{
        module: __MODULE__,
        status: :running,
        tree: bt_definition,
        cursor: root_node
      })

      # Later, read the state
      state = Strategy.State.get(agent)
      state.cursor  # => root_node
  """

  alias Jido.Agent

  @key :__strategy__

  @type status :: :idle | :running | :waiting | :success | :failure

  @type t :: %{
          optional(:module) => module(),
          optional(:status) => status(),
          optional(:data) => term(),
          optional(atom()) => term()
        }

  @doc """
  Returns the reserved key used for strategy state.
  """
  @spec key() :: atom()
  def key, do: @key

  @doc """
  Get the strategy state from an agent.
  Returns the default if no strategy state exists.
  """
  @spec get(Agent.t(), t()) :: t()
  def get(%Agent{state: state}, default \\ %{}) do
    Map.get(state, @key, default)
  end

  @doc """
  Put new strategy state into an agent.
  Replaces any existing strategy state.
  """
  @spec put(Agent.t(), t()) :: Agent.t()
  def put(%Agent{} = agent, new_state) when is_map(new_state) do
    Jido.Agent.StateBudget.replace!(agent, Map.put(agent.state, @key, new_state))
  end

  @doc """
  Update strategy state using a function.
  The function receives the current strategy state (or empty map) and returns the new state.
  """
  @spec update(Agent.t(), (t() -> t())) :: Agent.t()
  def update(%Agent{} = agent, fun) when is_function(fun, 1) do
    current = get(agent, %{})
    put(agent, fun.(current))
  end

  @doc """
  Get the current strategy status.
  Returns :idle if no status is set.
  """
  @spec status(Agent.t()) :: status()
  def status(%Agent{} = agent) do
    get(agent, %{}) |> Map.get(:status, :idle)
  end

  @doc """
  Set the strategy status.
  """
  @spec set_status(Agent.t(), status()) :: Agent.t()
  def set_status(%Agent{} = agent, status)
      when status in [:idle, :running, :waiting, :success, :failure] do
    update(agent, fn state -> Map.put(state, :status, status) end)
  end

  @doc """
  Check if the strategy is in a terminal state (success or failure).
  """
  @spec terminal?(Agent.t()) :: boolean()
  def terminal?(%Agent{} = agent) do
    status(agent) in [:success, :failure]
  end

  @doc """
  Check if the strategy is actively running (not idle or terminal).
  """
  @spec active?(Agent.t()) :: boolean()
  def active?(%Agent{} = agent) do
    status(agent) in [:running, :waiting]
  end

  @doc """
  Clear strategy state, resetting to empty map.
  """
  @spec clear(Agent.t()) :: Agent.t()
  def clear(%Agent{} = agent) do
    put(agent, %{})
  end
end
