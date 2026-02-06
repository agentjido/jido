defmodule Jido.Memory do
  @moduledoc """
  An agent's mutable cognitive substrate — what the agent currently believes and wants.

  Memory is stored under the reserved key `:__memory__` in `agent.state`. It
  complements Thread (append-only episodic log) and Strategy (execution control)
  as the third pillar of agent cognition.

  Memory is an open map of named spaces. Every agent starts with two built-in
  defaults — `tasks` (ordered list) and `world` (key-value map) — but custom
  spaces can be added for domain-specific cognitive structures.

  ## Examples

      memory = Memory.new()
      memory.spaces.world  #=> %Space{data: %{}, rev: 0}
      memory.spaces.tasks  #=> %Space{data: [], rev: 0}
  """

  alias Jido.Memory.Space

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(description: "Unique memory identifier"),
              rev:
                Zoi.integer(description: "Container-level monotonic revision")
                |> Zoi.default(0),
              spaces:
                Zoi.map(description: "Open map of named spaces")
                |> Zoi.default(%{}),
              created_at: Zoi.integer(description: "Creation timestamp (ms)"),
              updated_at: Zoi.integer(description: "Last update timestamp (ms)"),
              metadata: Zoi.map(description: "Arbitrary metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @reserved_spaces [:tasks, :world]

  @doc "Returns the Zoi schema for Memory."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Returns the list of reserved (non-deletable) space names."
  @spec reserved_spaces() :: [atom()]
  def reserved_spaces, do: @reserved_spaces

  @doc "Create a new memory with default world and tasks spaces."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    now = opts[:now] || System.system_time(:millisecond)

    %__MODULE__{
      id: opts[:id] || generate_id(),
      rev: 0,
      spaces: %{
        world: Space.new_kv(),
        tasks: Space.new_list()
      },
      created_at: now,
      updated_at: now,
      metadata: opts[:metadata] || %{}
    }
  end

  defp generate_id do
    "mem_" <> Jido.Util.generate_id()
  end
end
