defmodule Jido.Identity.Profile do
  @moduledoc """
  Helpers for reading and writing identity profile fields.
  """

  alias Jido.Agent
  alias Jido.Identity
  alias Jido.Identity.Agent, as: IdentityAgent

  @doc "Returns the age from identity profile, or nil if no identity"
  @spec age(Agent.t()) :: non_neg_integer() | nil
  def age(%Agent{} = agent) do
    case IdentityAgent.get(agent) do
      nil -> nil
      %Identity{profile: profile} -> Map.get(profile, :age)
    end
  end

  @doc "Get a key from the identity profile with a default"
  @spec get(Agent.t(), atom(), term()) :: term()
  def get(%Agent{} = agent, key, default \\ nil) do
    case IdentityAgent.get(agent) do
      nil -> default
      %Identity{profile: profile} -> Map.get(profile, key, default)
    end
  end

  @doc "Set a key in the identity profile"
  @spec put(Agent.t(), atom(), term()) :: Agent.t()
  def put(%Agent{} = agent, key, value) do
    IdentityAgent.update(agent, fn identity ->
      identity = identity || Identity.new()
      updated = %{identity | profile: Map.put(identity.profile, key, value)}
      Identity.bump(updated)
    end)
  end
end
