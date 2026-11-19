defmodule Jido.Thread.Entry do
  alias Jido.Joi
  alias Jido.Thread.Document
  @moduledoc "One portable entry in a `Jido.Thread`."

  @field_aliases Document.aliases([:id, :seq, :at, :kind, :payload, :refs, :__struct__])

  @schema Joi.struct(
            __MODULE__,
            %{
              id: Joi.string() |> Joi.min(1),
              seq: Joi.integer() |> Joi.min(0),
              at: Joi.integer(),
              kind: Joi.any(),
              payload: Joi.map() |> Joi.default(%{}),
              refs: Joi.map() |> Joi.default(%{})
            },
            unrecognized_keys: :error
          )

  @type kind :: atom() | String.t()
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  @doc "Returns the Entry schema."
  @spec schema() :: Joi.schema()
  def schema, do: @schema

  @doc "Creates an Entry. Its Thread assigns the final sequence number."
  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    seq = Document.default(Document.field(attrs, :seq), 0)
    normalize(attrs, seq, System.system_time(:millisecond))
  end

  @doc "Returns a portable encoded Entry map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = entry) do
    case encode_document(entry) do
      {:ok, document} -> document
      {:error, :invalid_entry} -> raise ArgumentError, "invalid thread entry"
    end
  end

  @doc false
  @spec encode_document(t()) :: {:ok, map()} | {:error, :invalid_entry}
  def encode_document(entry) do
    with {:ok, entry} <- validate(entry) do
      {:ok,
       %{
         "id" => entry.id,
         "seq" => entry.seq,
         "at" => entry.at,
         "kind" => encode_kind(entry.kind),
         "payload" => entry.payload,
         "refs" => entry.refs
       }}
    end
  end

  @doc "Decodes an Entry without creating atoms from input."
  @spec decode(t() | map()) :: {:ok, t()} | {:error, :invalid_entry}
  def decode(%__MODULE__{} = entry), do: validate(entry)

  def decode(attrs) when is_map(attrs) do
    with {:ok, fields} <- Document.normalize_fields(attrs, @field_aliases) do
      %__MODULE__{
        id: fields[:id],
        seq: fields[:seq],
        at: fields[:at],
        kind: decode_kind(fields[:kind]),
        payload: Document.default(fields[:payload], %{}),
        refs: Document.default(fields[:refs], %{})
      }
      |> validate()
    else
      :error -> {:error, :invalid_entry}
    end
  end

  def decode(_value), do: {:error, :invalid_entry}

  @doc false
  @spec validate(t()) :: {:ok, t()} | {:error, :invalid_entry}
  def validate(%__MODULE__{} = entry) do
    with :ok <- Joi.validate(@schema, entry),
         true <- (is_atom(entry.kind) and not is_nil(entry.kind)) or nonempty?(entry.kind),
         :ok <- Jido.Codec.Term.validate(entry.payload, :thread_entry_payload),
         :ok <- Jido.Codec.Term.validate(entry.refs, :thread_entry_refs) do
      {:ok, entry}
    else
      _other -> {:error, :invalid_entry}
    end
  end

  def validate(_value), do: {:error, :invalid_entry}

  @doc false
  @spec normalize(t() | map(), non_neg_integer(), integer()) :: t()
  def normalize(attrs, seq, now) when is_map(attrs) do
    id = Document.field(attrs, :id)

    %__MODULE__{
      id: if(is_nil(id), do: entry_id(), else: id),
      seq: seq,
      at: Document.default(Document.field(attrs, :at), now),
      kind: Document.default(Document.field(attrs, :kind), :note),
      payload: Document.default(Document.field(attrs, :payload), %{}),
      refs: Document.default(Document.field(attrs, :refs), %{})
    }
    |> validate!()
  end

  defp validate!(entry) do
    case validate(entry) do
      {:ok, valid} -> valid
      {:error, :invalid_entry} -> raise ArgumentError, "invalid thread entry"
    end
  end

  defp nonempty?(value), do: is_binary(value) and value != ""

  defp encode_kind(kind) when is_atom(kind),
    do: %{"type" => "atom", "value" => Atom.to_string(kind)}

  defp encode_kind(kind), do: %{"type" => "string", "value" => kind}

  defp decode_kind(%{"type" => "atom", "value" => kind}) when is_binary(kind) do
    String.to_existing_atom(kind)
  rescue
    ArgumentError -> nil
  end

  defp decode_kind(%{"type" => "string", "value" => kind}) when is_binary(kind), do: kind
  defp decode_kind(kind), do: kind
  defp entry_id, do: "entry_#{Jido.Id.uuid7()}"
end

defimpl Runic.Identity.Projectable, for: Jido.Thread.Entry do
  def identity_document(entry), do: Jido.Thread.Entry.encode(entry)
end
