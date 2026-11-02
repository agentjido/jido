defmodule Jido.Agent.Ref do
  @moduledoc """
  Stable identity for one logical Agent.

  A Ref identifies an Agent with the exact `{namespace, partition, id}` tuple.
  It does not contain runtime location, process, Agent module, definition
  revision (`vsn`), activation, or storage revision data.

  A Ref is an identifier. It is not a credential or an authorization value.
  """

  alias Jido.Error

  @version 1

  @nonempty_binary_schema Zoi.string(description: "Nonempty Agent identity value")
                          |> Zoi.refine({__MODULE__, :validate_nonempty_binary, []})

  @fields %{
    namespace: @nonempty_binary_schema,
    partition:
      @nonempty_binary_schema
      |> Zoi.nullable()
      |> Zoi.default(nil),
    id: @nonempty_binary_schema
  }

  @schema Zoi.struct(__MODULE__, @fields, unrecognized_keys: :error)
  @attrs_schema Zoi.map(@fields, unrecognized_keys: :error)

  @map_schema Zoi.map(
                %{
                  "version" => Zoi.literal(@version),
                  "namespace" => @nonempty_binary_schema,
                  "partition" => @nonempty_binary_schema |> Zoi.nullable(),
                  "id" => @nonempty_binary_schema
                },
                unrecognized_keys: :error
              )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the static schema for an Agent Ref."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates and validates one Agent Ref."
  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Error.ValidationError.t()}
  def new(%__MODULE__{} = ref), do: validate(ref)

  def new(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      attrs
      |> Map.new()
      |> new()
    else
      invalid("Agent Ref attributes must be a map or keyword list", %{value: attrs})
    end
  end

  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    case Zoi.parse(@attrs_schema, attrs) do
      {:ok, parsed} -> {:ok, struct!(__MODULE__, parsed)}
      {:error, issues} -> invalid("Agent Ref attributes are invalid", %{issues: issues})
    end
  end

  def new(value),
    do: invalid("Agent Ref attributes must be a map or keyword list", %{value: value})

  @doc "Creates one Agent Ref or raises its validation error."
  @spec new!(map() | keyword() | t()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, ref} -> ref
      {:error, error} -> raise error
    end
  end

  @doc "Validates one Agent Ref without changing its identity fields."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.ValidationError.t()}
  def validate(%__MODULE__{} = ref) do
    case Zoi.parse(@schema, ref) do
      {:ok, validated} -> {:ok, validated}
      {:error, issues} -> invalid("Agent Ref is invalid", %{issues: issues})
    end
  end

  def validate(value), do: invalid("Expected a Jido.Agent.Ref value", %{value: value})

  @doc "Returns the exact version-1 public map for one Agent Ref."
  @spec to_map(term()) :: {:ok, map()} | {:error, Error.ValidationError.t()}
  def to_map(%__MODULE__{} = ref) do
    case validate(ref) do
      {:ok, validated} ->
        {:ok,
         %{
           "version" => @version,
           "namespace" => validated.namespace,
           "partition" => validated.partition,
           "id" => validated.id
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  def to_map(value), do: invalid("Expected a Jido.Agent.Ref value", %{value: value})

  @doc "Returns the exact version-1 public map or raises its validation error."
  @spec to_map!(term()) :: map() | no_return()
  def to_map!(value) do
    case to_map(value) do
      {:ok, value} -> value
      {:error, error} -> raise error
    end
  end

  @doc "Decodes and validates one exact version-1 Agent Ref map."
  @spec from_map(term()) :: {:ok, t()} | {:error, Error.ValidationError.t()}
  def from_map(value) do
    case Zoi.parse(@map_schema, value) do
      {:ok, decoded} ->
        {:ok,
         %__MODULE__{
           namespace: decoded["namespace"],
           partition: decoded["partition"],
           id: decoded["id"]
         }}

      {:error, issues} ->
        invalid("Agent Ref map is invalid", %{issues: issues})
    end
  end

  @doc "Decodes one exact version-1 Agent Ref map or raises its validation error."
  @spec from_map!(term()) :: t() | no_return()
  def from_map!(value) do
    case from_map(value) do
      {:ok, ref} -> ref
      {:error, error} -> raise error
    end
  end

  @doc false
  @spec validate_nonempty_binary(term(), term()) :: :ok | {:error, String.t()}
  def validate_nonempty_binary(value, _context)
      when is_binary(value) and byte_size(value) > 0,
      do: :ok

  def validate_nonempty_binary(_value, _context), do: {:error, "must be a nonempty binary"}

  defp invalid(message, details) do
    {:error,
     Error.validation_error(message,
       kind: :input,
       subject: __MODULE__,
       details: details
     )}
  end
end
