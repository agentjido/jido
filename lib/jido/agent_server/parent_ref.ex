defmodule Jido.AgentServer.ParentRef do
  @moduledoc "A private logical parent relationship for one live Agent Server."

  @schema Zoi.struct(
            __MODULE__,
            %{
              pid: Zoi.pid(description: "Live parent Agent Server PID"),
              ref:
                Zoi.reference(description: "Parent process monitor")
                |> Zoi.nullable()
                |> Zoi.optional(),
              id: Zoi.string(description: "Parent Agent id") |> Zoi.min(1),
              partition: Zoi.any(description: "Parent partition") |> Zoi.optional(),
              tag: Zoi.any(description: "Relationship tag"),
              spawn_ref:
                Zoi.tuple(
                  {Zoi.integer(description: "Remote request generation") |> Zoi.min(1),
                   Zoi.reference(description: "Remote request reference")},
                  description: "Private remote creation request identity"
                )
                |> Zoi.nullable()
                |> Zoi.optional(),
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
  def new(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs), do: attrs |> Map.new() |> new(), else: invalid(attrs)
  end

  def new(%__MODULE__{} = parent), do: parent |> Map.from_struct() |> new()

  def new(attrs) when is_map(attrs) do
    case Zoi.parse(@schema, attrs) do
      {:ok, parent} -> {:ok, parent}
      {:error, issues} -> invalid(attrs, issues)
    end
  end

  def new(value), do: invalid(value)

  defp invalid(value, issues \\ nil) do
    details = if issues, do: %{value: value, issues: issues}, else: %{value: value}

    {:error, Jido.Error.validation_error("Agent parent reference is invalid", details: details)}
  end

  @doc "Creates one validated parent relationship or raises."
  def new!(attrs) do
    case new(attrs) do
      {:ok, parent} -> parent
      {:error, error} -> raise error
    end
  end
end
