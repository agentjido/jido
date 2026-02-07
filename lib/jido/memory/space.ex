defmodule Jido.Memory.Space do
  @moduledoc """
  The unit of memory — a named container with typed data and revision tracking.

  A Space holds either a map (key-value) or list (ordered items) in its `data`
  field. The type is determined by the data itself — pattern matching and guards
  (`is_map/1`, `is_list/1`) handle dispatch.

  Each space tracks its own revision counter independently, enabling fine-grained
  concurrency control.

  ## Examples

      # Key-value space (world model)
      world = Space.new_kv()
      world = %{world | data: Map.put(world.data, :temperature, 22)}

      # List space (task list)
      tasks = Space.new_list()
      tasks = %{tasks | data: tasks.data ++ [%{id: "t1", text: "Check sensor"}]}
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              data: Zoi.any(description: "Space contents — a map or list"),
              rev:
                Zoi.integer(description: "Per-space revision, increments on mutation")
                |> Zoi.default(0),
              metadata: Zoi.map(description: "Space-level metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Space."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Create a new space from attributes."
  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      data: Map.get(attrs, :data, %{}),
      rev: Map.get(attrs, :rev, 0),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  @doc "Create a new key-value (map) space."
  @spec new_kv(keyword()) :: t()
  def new_kv(opts \\ []) do
    %__MODULE__{
      data: Keyword.get(opts, :data, %{}),
      rev: 0,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc "Create a new list space."
  @spec new_list(keyword()) :: t()
  def new_list(opts \\ []) do
    %__MODULE__{
      data: Keyword.get(opts, :data, []),
      rev: 0,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc "Returns true if the space holds map data."
  @spec map?(t()) :: boolean()
  def map?(%__MODULE__{data: data}) when is_map(data), do: true
  def map?(%__MODULE__{}), do: false

  @doc "Returns true if the space holds list data."
  @spec list?(t()) :: boolean()
  def list?(%__MODULE__{data: data}) when is_list(data), do: true
  def list?(%__MODULE__{}), do: false
end
