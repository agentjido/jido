defmodule Jido.AgentServer.ChildInfo do
  @moduledoc "Private process and identity data for one tracked Agent or Plugin child."

  @schema Zoi.struct(
            __MODULE__,
            %{
              pid: Zoi.any(description: "Tracked process PID"),
              lifecycle_pid:
                Zoi.any(description: "Optional process that owns the tracked child")
                |> Zoi.optional(),
              ref: Zoi.any(description: "Process monitor reference"),
              module: Zoi.atom(description: "Agent or Plugin module"),
              id: Zoi.string(description: "Stable child identifier"),
              activation_id:
                Zoi.string(description: "Child activation identity") |> Zoi.optional(),
              creation_cause:
                Jido.AgentServer.CreationCause.schema() |> Zoi.nullable() |> Zoi.optional(),
              partition: Zoi.any(description: "Child partition") |> Zoi.optional(),
              tag: Zoi.any(description: "Owner-local tag"),
              kind: Zoi.atom(description: "Tracked process kind") |> Zoi.default(:agent),
              meta: Zoi.map(description: "Relationship metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Creates one validated child record."
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()
  def new(attrs) when is_map(attrs), do: Zoi.parse(@schema, attrs)

  def new(value) do
    {:error,
     Jido.Error.validation_error("Agent child information must be a map",
       details: %{value: value}
     )}
  end

  @doc "Creates one validated child record or raises."
  def new!(attrs) do
    case new(attrs) do
      {:ok, child} -> child
      {:error, error} -> raise error
    end
  end
end
