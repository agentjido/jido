defmodule Jido.Identity.Agent do
  @moduledoc """
  Helper for managing Identity in agent state.

  Identity is stored at the reserved key `:__identity__` in `agent.state`.
  """

  alias Jido.Agent
  alias Jido.Identity

  @key :__identity__

  @doc "Returns the reserved key for identity storage"
  @spec key() :: atom()
  def key, do: @key

  @doc "Get identity from agent state"
  @spec get(Agent.t(), Identity.t() | nil) :: Identity.t() | nil
  def get(%Agent{state: state}, default \\ nil) do
    Map.get(state, @key, default)
  end

  @doc "Put identity into agent state"
  @spec put(Agent.t(), Identity.t()) :: Agent.t()
  def put(%Agent{} = agent, %Identity{} = identity) do
    %{agent | state: Map.put(agent.state, @key, identity)}
  end

  @doc "Update identity using a function"
  @spec update(Agent.t(), (Identity.t() | nil -> Identity.t())) :: Agent.t()
  def update(%Agent{} = agent, fun) when is_function(fun, 1) do
    current = get(agent)
    put(agent, fun.(current))
  end

  @doc "Ensure agent has an identity (initialize if missing)"
  @spec ensure(Agent.t(), keyword()) :: Agent.t()
  def ensure(%Agent{} = agent, opts \\ []) do
    case get(agent) do
      nil -> put(agent, Identity.new(opts))
      _identity -> agent
    end
  end

  @doc "Check if agent has an identity"
  @spec has_identity?(Agent.t()) :: boolean()
  def has_identity?(%Agent{} = agent), do: get(agent) != nil

  # ---------------------------------------------------------------------------
  # Profile convenience
  # ---------------------------------------------------------------------------

  @doc "Returns the age from identity profile, or nil if no identity"
  @spec age(Agent.t()) :: non_neg_integer() | nil
  def age(%Agent{} = agent) do
    case get(agent) do
      nil -> nil
      %Identity{profile: profile} -> Map.get(profile, :age)
    end
  end

  @doc "Get a key from the identity profile with a default"
  @spec get_profile(Agent.t(), atom(), term()) :: term()
  def get_profile(%Agent{} = agent, key, default \\ nil) do
    case get(agent) do
      nil -> default
      %Identity{profile: profile} -> Map.get(profile, key, default)
    end
  end

  @doc "Set a key in the identity profile"
  @spec put_profile(Agent.t(), atom(), term()) :: Agent.t()
  def put_profile(%Agent{} = agent, key, value) do
    mutate(agent, fn identity ->
      %{identity | profile: Map.put(identity.profile, key, value)}
    end)
  end

  # ---------------------------------------------------------------------------
  # Capability queries
  # ---------------------------------------------------------------------------

  @doc "Returns the capabilities map"
  @spec capabilities(Agent.t()) :: map()
  def capabilities(%Agent{} = agent) do
    case get(agent) do
      nil -> %{actions: [], tags: [], io: %{}, limits: %{}}
      %Identity{capabilities: caps} -> caps
    end
  end

  @doc "Check if action_id is in capabilities.actions"
  @spec supports_action?(Agent.t(), term()) :: boolean()
  def supports_action?(%Agent{} = agent, action_id) do
    action_id in capabilities(agent)[:actions]
  end

  @doc "Check if tag is in capabilities.tags"
  @spec has_tag?(Agent.t(), term()) :: boolean()
  def has_tag?(%Agent{} = agent, tag) do
    tag in capabilities(agent)[:tags]
  end

  @doc "Returns list of actions from capabilities"
  @spec actions(Agent.t()) :: list()
  def actions(%Agent{} = agent), do: capabilities(agent)[:actions]

  @doc "Returns list of tags from capabilities"
  @spec tags(Agent.t()) :: list()
  def tags(%Agent{} = agent), do: capabilities(agent)[:tags]

  # ---------------------------------------------------------------------------
  # Capability mutations
  # ---------------------------------------------------------------------------

  @doc "Add an action_id to capabilities.actions (no duplicates)"
  @spec add_action(Agent.t(), term()) :: Agent.t()
  def add_action(%Agent{} = agent, action_id) do
    mutate(agent, fn identity ->
      actions = identity.capabilities[:actions] || []

      if action_id in actions do
        identity
      else
        put_in_caps(identity, :actions, actions ++ [action_id])
      end
    end)
  end

  @doc "Remove an action_id from capabilities.actions"
  @spec remove_action(Agent.t(), term()) :: Agent.t()
  def remove_action(%Agent{} = agent, action_id) do
    mutate(agent, fn identity ->
      actions = identity.capabilities[:actions] || []
      put_in_caps(identity, :actions, List.delete(actions, action_id))
    end)
  end

  @doc "Add a tag to capabilities.tags (no duplicates)"
  @spec add_tag(Agent.t(), term()) :: Agent.t()
  def add_tag(%Agent{} = agent, tag) do
    mutate(agent, fn identity ->
      tags = identity.capabilities[:tags] || []

      if tag in tags do
        identity
      else
        put_in_caps(identity, :tags, tags ++ [tag])
      end
    end)
  end

  @doc "Set a limit key/value in capabilities.limits"
  @spec set_limit(Agent.t(), atom(), term()) :: Agent.t()
  def set_limit(%Agent{} = agent, key, value) do
    mutate(agent, fn identity ->
      limits = identity.capabilities[:limits] || %{}
      put_in_caps(identity, :limits, Map.put(limits, key, value))
    end)
  end

  @doc "Set an io key/value in capabilities.io"
  @spec set_io(Agent.t(), atom(), term()) :: Agent.t()
  def set_io(%Agent{} = agent, key, value) do
    mutate(agent, fn identity ->
      io = identity.capabilities[:io] || %{}
      put_in_caps(identity, :io, Map.put(io, key, value))
    end)
  end

  # ---------------------------------------------------------------------------
  # Extension operations
  # ---------------------------------------------------------------------------

  @doc "Get extension by plugin_name with a default"
  @spec get_extension(Agent.t(), atom(), term()) :: term()
  def get_extension(%Agent{} = agent, plugin_name, default \\ nil) do
    case get(agent) do
      nil -> default
      %Identity{extensions: exts} -> Map.get(exts, plugin_name, default)
    end
  end

  @doc "Put extension map for plugin_name"
  @spec put_extension(Agent.t(), atom(), map()) :: Agent.t()
  def put_extension(%Agent{} = agent, plugin_name, ext) when is_map(ext) do
    mutate(agent, fn identity ->
      %{identity | extensions: Map.put(identity.extensions, plugin_name, ext)}
    end)
  end

  @doc "Shallow merge patch into extension for plugin_name"
  @spec merge_extension(Agent.t(), atom(), map()) :: Agent.t()
  def merge_extension(%Agent{} = agent, plugin_name, patch) when is_map(patch) do
    mutate(agent, fn identity ->
      current = Map.get(identity.extensions, plugin_name, %{})

      %{
        identity
        | extensions: Map.put(identity.extensions, plugin_name, Map.merge(current, patch))
      }
    end)
  end

  @doc "Update extension via function"
  @spec update_extension(Agent.t(), atom(), (map() | nil -> map())) :: Agent.t()
  def update_extension(%Agent{} = agent, plugin_name, fun) when is_function(fun, 1) do
    mutate(agent, fn identity ->
      current = Map.get(identity.extensions, plugin_name)
      %{identity | extensions: Map.put(identity.extensions, plugin_name, fun.(current))}
    end)
  end

  # ---------------------------------------------------------------------------
  # Snapshot
  # ---------------------------------------------------------------------------

  @doc "Return a public snapshot of the agent's identity"
  @spec snapshot(Agent.t()) :: map() | nil
  def snapshot(%Agent{} = agent) do
    case get(agent) do
      nil -> nil
      %Identity{} = identity -> Identity.snapshot(identity)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp mutate(%Agent{} = agent, fun) when is_function(fun, 1) do
    identity = get(agent) || Identity.new()
    updated = fun.(identity)
    put(agent, bump(updated))
  end

  defp bump(%Identity{} = identity) do
    %{identity | rev: identity.rev + 1, updated_at: System.system_time(:millisecond)}
  end

  defp put_in_caps(%Identity{} = identity, key, value) do
    %{identity | capabilities: Map.put(identity.capabilities, key, value)}
  end
end
