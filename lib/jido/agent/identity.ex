defmodule Jido.Agent.Identity do
  @moduledoc """
  Agent identity state for lifecycle/profile facts.

  The identity is stored at the reserved `:__identity__` key in agent state
  and captures lifecycle facts such as age, origin, and generation. The core
  agent identity lives under `Jido.Agent` so the top-level `Jido.Identity`
  namespace can be owned by identity extensions such as the external
  `jido_identity` package.

  This module used to be named `Jido.Identity`. The module namespace moved so
  the core framework's agent identity state does not conflict with top-level
  identity modules. The state key, default plugin metadata name, default
  `:identity` capability, and `"identity_evolve"` action name remain anchored
  to the existing `:__identity__` plugin state slice.

  Identity state is immutable — updates produce a new struct with a bumped
  revision.
  """

  @state_key :__identity__
  @legacy_identity_module Jido.Identity

  @schema Zoi.struct(
            __MODULE__,
            %{
              rev:
                Zoi.integer(description: "Monotonic revision")
                |> Zoi.default(0),
              profile:
                Zoi.map(description: "Lifecycle facts")
                |> Zoi.default(%{age: nil}),
              created_at: Zoi.integer(description: "Creation timestamp (ms)"),
              updated_at: Zoi.integer(description: "Last update timestamp (ms)")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the reserved agent state key used for identity storage."
  @spec state_key() :: :__identity__
  def state_key, do: @state_key

  @doc "Create a new identity."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    now = opts[:now] || System.system_time(:millisecond)

    %__MODULE__{
      rev: 0,
      profile: opts[:profile] || %{age: nil},
      created_at: now,
      updated_at: now
    }
  end

  @doc "Pure evolution — increments profile age and bumps revision."
  @spec evolve(t(), keyword()) :: t()
  def evolve(%__MODULE__{} = identity, opts \\ []) do
    years = opts[:years] || 0
    days = opts[:days] || 0
    now = opts[:now] || System.system_time(:millisecond)
    age_increment = years + div(days, 365)
    current_age = identity.profile[:age] || 0

    %{
      identity
      | profile: Map.put(identity.profile, :age, current_age + age_increment)
    }
    |> bump(now: now)
  end

  @doc "Return a public snapshot of the identity."
  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{} = identity) do
    %{
      profile: Map.take(identity.profile, [:age, :generation, :origin])
    }
  end

  @doc "Bump identity revision and updated_at timestamp."
  @spec bump(t(), keyword()) :: t()
  def bump(%__MODULE__{} = identity, opts \\ []) do
    now = opts[:now] || System.system_time(:millisecond)
    %{identity | rev: identity.rev + 1, updated_at: now}
  end

  @doc """
  Converts legacy `%Jido.Identity{}` agent identity structs to `%#{inspect(__MODULE__)}{}`.

  This helper supports persisted checkpoints created before the identity
  namespace moved out of `Jido.Identity`. Values that are already identities,
  custom plugin state, or invalid legacy shapes are returned unchanged.
  """
  @spec migrate_legacy(term()) :: t() | term()
  def migrate_legacy(%__MODULE__{} = identity), do: identity

  def migrate_legacy(
        %{
          __struct__: @legacy_identity_module,
          rev: rev,
          profile: profile,
          created_at: created_at,
          updated_at: updated_at
        } = legacy_identity
      )
      when map_size(legacy_identity) == 5 and is_integer(rev) and is_map(profile) and
             is_integer(created_at) and is_integer(updated_at) do
    %__MODULE__{
      rev: rev,
      profile: profile,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  def migrate_legacy(value), do: value

  @doc """
  Migrates the identity value inside an agent state map.

  The state key is still `:__identity__`; only the struct module is migrated.
  """
  @spec migrate_state(map()) :: map()
  def migrate_state(%{} = state) do
    case Map.fetch(state, @state_key) do
      {:ok, value} -> Map.put(state, @state_key, migrate_legacy(value))
      :error -> state
    end
  end

  @doc """
  Migrates a checkpoint map's `:state` identity value when present.
  """
  @spec migrate_checkpoint(map()) :: map()
  def migrate_checkpoint(%{} = checkpoint) do
    case Map.fetch(checkpoint, :state) do
      {:ok, state} when is_map(state) -> %{checkpoint | state: migrate_state(state)}
      _other -> checkpoint
    end
  end
end
