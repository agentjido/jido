defmodule Jido.Agent.Ref do
  alias Jido.Joi

  @moduledoc """
  Stable identity for one logical Agent.

  A Ref identifies an Agent with the exact `{namespace, partition, id}` tuple.
  It does not contain runtime location, process, Agent module, definition
  revision (`vsn`), activation, or storage revision data.

  A Ref is an identifier. It is not a credential or an authorization value.
  """

  alias Jido.Error

  @version 1

  @nonempty_binary_schema Joi.string(description: "Nonempty Agent identity value")
                          |> Joi.refine({__MODULE__, :validate_nonempty_binary, []})

  @fields %{
    namespace: @nonempty_binary_schema,
    partition:
      @nonempty_binary_schema
      |> Joi.nullable()
      |> Joi.default(nil),
    id: @nonempty_binary_schema
  }

  @schema Joi.struct(__MODULE__, @fields, unrecognized_keys: :error)
  @attrs_schema Joi.map(@fields, unrecognized_keys: :error)

  @map_schema Joi.map(
                %{
                  "version" => Joi.literal(@version),
                  "namespace" => @nonempty_binary_schema,
                  "partition" => @nonempty_binary_schema |> Joi.nullable(),
                  "id" => @nonempty_binary_schema
                },
                unrecognized_keys: :error
              )

  @type t :: unquote(Joi.type_spec(@schema))

  @enforce_keys Joi.Struct.enforce_keys(@schema)
  defstruct Joi.Struct.struct_fields(@schema)

  @doc "Returns the static schema for an Agent Ref."
  @spec schema() :: Joi.schema()
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
    case Joi.parse(@attrs_schema, attrs) do
      {:ok, parsed} -> {:ok, struct!(__MODULE__, parsed)}
      {:error, issues} -> invalid("Agent Ref attributes are invalid", %{issues: issues})
    end
  end

  def new(value),
    do: invalid("Agent Ref attributes must be a map or keyword list", %{value: value})

  @doc false
  @spec new_scoped(String.t(), term(), term()) ::
          {:ok, t()} | {:error, Error.ValidationError.t()}
  def new_scoped(namespace, id, opts) when is_binary(id) do
    with :ok <- validate_option_list(opts, "Agent Ref options"),
         :ok <- validate_ref_option_keys(opts) do
      new(namespace: namespace, partition: Keyword.get(opts, :partition), id: id)
    end
  end

  def new_scoped(_namespace, id, _opts),
    do: invalid_config("Agent Ref ID must be a binary", %{id: id})

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
    case Joi.parse(@schema, ref) do
      {:ok, validated} -> {:ok, validated}
      {:error, issues} -> invalid("Agent Ref is invalid", %{issues: issues})
    end
  end

  def validate(value), do: invalid("Expected a Jido.Agent.Ref value", %{value: value})

  @doc false
  @spec validate_namespace(term(), String.t()) ::
          {:ok, t()} | {:error, Error.ValidationError.t()}
  def validate_namespace(value, namespace) do
    with {:ok, ref} <- validate(value) do
      if ref.namespace == namespace do
        {:ok, ref}
      else
        invalid_config("Agent Ref namespace does not match the Jido instance", %{
          code: :jido_namespace_mismatch,
          expected: namespace,
          actual: ref.namespace
        })
      end
    end
  end

  @doc false
  @spec startup_options(t(), term()) ::
          {:ok, keyword()} | {:error, Error.ValidationError.t()}
  def startup_options(%__MODULE__{} = ref, opts) do
    with :ok <- validate_option_list(opts, "Agent Ref startup options"),
         :ok <- matching_option(opts, :id, ref.id),
         :ok <- matching_option(opts, :partition, ref.partition) do
      {:ok,
       opts
       |> Keyword.put(:id, ref.id)
       |> Keyword.put(:partition, ref.partition)}
    end
  end

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
    case Joi.parse(@map_schema, value) do
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

  defp validate_option_list(opts, label) do
    if Keyword.keyword?(opts) do
      keys = Keyword.keys(opts)

      case keys -- Enum.uniq(keys) do
        [] ->
          :ok

        duplicates ->
          invalid_config("#{label} must contain unique keys", %{
            keys: Enum.uniq(duplicates)
          })
      end
    else
      invalid_config("#{label} must be a keyword list", %{value: opts})
    end
  end

  defp validate_ref_option_keys(opts) do
    case Enum.reject(Keyword.keys(opts), &(&1 == :partition)) do
      [] -> :ok
      keys -> invalid_config("Agent Ref options have unknown keys", %{keys: keys})
    end
  end

  defp matching_option(opts, key, expected) do
    case Keyword.fetch(opts, key) do
      :error ->
        :ok

      {:ok, ^expected} ->
        :ok

      {:ok, value} ->
        invalid_config("Agent Ref conflicts with startup options", %{key: key, value: value})
    end
  end

  defp invalid_config(message, details) do
    {:error,
     Error.validation_error(message,
       kind: :input,
       subject: __MODULE__,
       details: Map.put_new(details, :code, :jido_instance_invalid_config)
     )}
  end

  defp invalid(message, details) do
    {:error,
     Error.validation_error(message,
       kind: :input,
       subject: __MODULE__,
       details: details
     )}
  end
end
