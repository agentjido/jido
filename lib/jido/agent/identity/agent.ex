defmodule Jido.Agent.Identity.Agent do
  @moduledoc """
  Helper for managing identity state in an agent.

  Identity state is stored at the reserved key `:__identity__` in `agent.state`.
  """

  alias Jido.Agent
  alias Jido.Agent.Identity

  @key :__identity__

  @doc "Returns the reserved key for identity storage."
  @spec key() :: atom()
  def key, do: @key

  @doc "Get identity state from agent state."
  @spec get(Agent.t(), Identity.t() | nil) :: Identity.t() | nil
  def get(%Agent{state: state}, default \\ nil) do
    state
    |> Map.get(@key, default)
    |> Identity.migrate_legacy()
  end

  @doc "Put identity state into agent state."
  @spec put(Agent.t(), Identity.t()) :: Agent.t()
  def put(%Agent{} = agent, %Identity{} = identity) do
    %{agent | state: Map.put(agent.state, @key, identity)}
  end

  @doc "Update identity state using a function."
  @spec update(Agent.t(), (Identity.t() | nil -> Identity.t())) :: Agent.t()
  def update(%Agent{} = agent, fun) when is_function(fun, 1) do
    current = get(agent)
    put(agent, fun.(current))
  end

  @doc "Ensure agent has an identity, initializing it when missing."
  @spec ensure(Agent.t(), keyword()) :: Agent.t()
  def ensure(%Agent{} = agent, opts \\ []) do
    case agent.state |> Map.get(@key) |> Identity.migrate_legacy() do
      nil -> put(agent, Identity.new(opts))
      %Identity{} = identity -> put(agent, identity)
      _custom_identity -> agent
    end
  end

  @doc "Check if agent has identity state."
  @spec has_identity?(Agent.t()) :: boolean()
  def has_identity?(%Agent{} = agent), do: get(agent) != nil

  # ---------------------------------------------------------------------------
  # Snapshot
  # ---------------------------------------------------------------------------

  @doc "Return a public snapshot of the agent's identity."
  @spec snapshot(Agent.t()) :: map() | nil
  def snapshot(%Agent{} = agent) do
    case get(agent) do
      nil -> nil
      %Identity{} = identity -> Identity.snapshot(identity)
    end
  end
end
