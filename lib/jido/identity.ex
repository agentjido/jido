defmodule Jido.Identity do
  @moduledoc """
  A first-class agent primitive representing who the agent is.

  Identity is stored at the `:__identity__` key in agent state and captures
  lifecycle facts (profile).

  Identity is immutable — updates produce a new struct with a bumped revision.
  """

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

  @doc "Create a new identity"
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

  @doc "Pure evolution — increments age and bumps revision"
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

  @doc "Return a public snapshot of the identity"
  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{} = identity) do
    %{
      profile: Map.take(identity.profile, [:age, :generation, :origin])
    }
  end

  @doc "Bump identity revision and updated_at timestamp"
  @spec bump(t(), keyword()) :: t()
  def bump(%__MODULE__{} = identity, opts \\ []) do
    now = opts[:now] || System.system_time(:millisecond)
    %{identity | rev: identity.rev + 1, updated_at: now}
  end
end
