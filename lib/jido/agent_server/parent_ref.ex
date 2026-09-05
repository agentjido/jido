defmodule Jido.AgentServer.ParentRef do
  @moduledoc "A private logical parent relationship for one live Agent Server."

  @schema Zoi.struct(
            __MODULE__,
            %{
              pid: Zoi.any(description: "Live parent Agent Server PID"),
              ref: Zoi.any(description: "Parent process monitor") |> Zoi.optional(),
              id: Zoi.string(description: "Parent Agent id"),
              partition: Zoi.any(description: "Parent partition") |> Zoi.optional(),
              tag: Zoi.any(description: "Relationship tag"),
              spawn_ref:
                Zoi.any(description: "Private remote creation request identity") |> Zoi.optional(),
              creation_cause:
                Jido.AgentServer.CreationCause.schema() |> Zoi.nullable() |> Zoi.optional(),
              meta: Zoi.map(description: "Relationship metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Creates one validated parent relationship."
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()
  def new(attrs) when is_map(attrs), do: Zoi.parse(@schema, attrs)

  def new(value) do
    {:error,
     Jido.Error.validation_error("Agent parent reference must be a map",
       details: %{value: value}
     )}
  end

  @doc "Creates one validated parent relationship or raises."
  def new!(attrs) do
    case new(attrs) do
      {:ok, parent} -> parent
      {:error, error} -> raise error
    end
  end
end
