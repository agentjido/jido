defmodule Jido.Pod.Topology.Link do
  @moduledoc """
  Canonical link definition for a pod topology.

  Links describe relationships between named topology nodes. In v1 they support
  a small fixed vocabulary and primarily drive eager reconciliation ordering.
  """

  @valid_types [:depends_on, :owns]

  @schema Zoi.struct(
            __MODULE__,
            %{
              type:
                Zoi.atom(description: "The relationship type.")
                |> Zoi.refine({__MODULE__, :validate_type, []}),
              from: Zoi.atom(description: "The source node name."),
              to: Zoi.atom(description: "The target node name."),
              meta:
                Zoi.map(description: "Optional metadata associated with the link.")
                |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc """
  Builds a validated topology link.

  Tuple shorthand `{type, from, to}` and `{type, from, to, meta}` is supported
  for backward compatibility.
  """
  @spec new(t() | tuple() | keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = link) do
    validate_distinct_endpoints(link)
  end

  def new({type, from, to}) do
    new(%{type: type, from: from, to: to})
  end

  def new({type, from, to, meta}) when is_map(meta) do
    new(%{type: type, from: from, to: to, meta: meta})
  end

  def new(attrs) when is_list(attrs) do
    new(Map.new(attrs))
  end

  def new(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new(:meta, %{})

    with {:ok, link} <- Zoi.parse(@schema, attrs) do
      validate_distinct_endpoints(link)
    end
  end

  def new(other) do
    {:error,
     Jido.Error.validation_error(
       "Topology links must be structs, tuples, maps, or keyword lists.",
       details: %{link: other}
     )}
  end

  @doc """
  Builds a validated topology link, raising on error.
  """
  @spec new!(t() | tuple() | keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, link} ->
        link

      {:error, reason} ->
        raise Jido.Error.validation_error("Invalid pod topology link", details: reason)
    end
  end

  @doc false
  @spec validate_type(atom(), keyword()) :: :ok | {:error, String.t()}
  def validate_type(value, _opts \\ [])
  def validate_type(value, _opts) when value in @valid_types, do: :ok

  def validate_type(value, _opts) do
    {:error, "expected link type to be one of #{inspect(@valid_types)}, got: #{inspect(value)}"}
  end

  defp validate_distinct_endpoints(%__MODULE__{from: from, to: to} = link) do
    if from == to do
      {:error,
       Jido.Error.validation_error(
         "Topology links cannot point to the same node.",
         details: %{from: from, to: to}
       )}
    else
      {:ok, link}
    end
  end
end
