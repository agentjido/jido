defmodule Jido.Examples.Plugins.PersistedState.AgentFacet do
  @moduledoc "Owns the Agent's integer state value."
  use Jido.Agent.Plugin

  @impl true
  def state_spec(_opts), do: {:owned, Zoi.integer() |> Zoi.default(0)}
end

defmodule Jido.Examples.Plugins.PersistedState.PersistenceFacet do
  @moduledoc "Converts only the owned integer to and from its stored value."
  use Jido.Persistence.Plugin

  @owned_prefix "owned:"

  @impl true
  def dump(value, _context, _opts) when is_integer(value),
    do: {:ok, @owned_prefix <> Integer.to_string(value)}

  @impl true
  def load(@owned_prefix <> encoded, _context, _opts) do
    case Integer.parse(encoded) do
      {value, ""} -> {:ok, value}
      _invalid -> {:error, :invalid_owned_value}
    end
  end

  def load(_value, _context, _opts), do: {:error, :invalid_owned_value}
end

defmodule Jido.Examples.Plugins.PersistedState.Package do
  @moduledoc "Pairs one Agent-owned state value with its Persistence facet."
  use Jido.Plugin,
    agent: Jido.Examples.Plugins.PersistedState.AgentFacet,
    persistence: Jido.Examples.Plugins.PersistedState.PersistenceFacet
end
