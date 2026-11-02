defmodule Jido.Thread.Entry do
  @moduledoc "One portable entry in a `Jido.Thread`."

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string() |> Zoi.min(1),
              seq: Zoi.integer() |> Zoi.min(0),
              at: Zoi.integer(),
              kind: Zoi.any(),
              payload: Zoi.map() |> Zoi.default(%{}),
              refs: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @type kind :: atom() | String.t()
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Entry schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates an Entry. Its Thread assigns the final sequence number."
  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: field(attrs, :id) || entry_id(),
      seq: field(attrs, :seq) || 0,
      at: field(attrs, :at) || System.system_time(:millisecond),
      kind: field(attrs, :kind) || :note,
      payload: field(attrs, :payload) || %{},
      refs: field(attrs, :refs) || %{}
    }
    |> validate!()
  end

  @doc "Returns a portable encoded Entry map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = entry) do
    %{
      "id" => entry.id,
      "seq" => entry.seq,
      "at" => entry.at,
      "kind" => encode_kind(entry.kind),
      "payload" => entry.payload,
      "refs" => entry.refs
    }
  end

  @doc "Decodes an Entry without creating atoms from input."
  @spec decode(t() | map()) :: {:ok, t()} | {:error, :invalid_entry}
  def decode(%__MODULE__{} = entry), do: validate(entry)

  def decode(attrs) when is_map(attrs) do
    if known_keys?(attrs, ~w(id seq at kind payload refs __struct__)) do
      %__MODULE__{
        id: field(attrs, :id),
        seq: field(attrs, :seq),
        at: field(attrs, :at),
        kind: decode_kind(field(attrs, :kind)),
        payload: field(attrs, :payload) || %{},
        refs: field(attrs, :refs) || %{}
      }
      |> validate()
    else
      {:error, :invalid_entry}
    end
  end

  def decode(_value), do: {:error, :invalid_entry}

  @doc false
  @spec validate(t()) :: {:ok, t()} | {:error, :invalid_entry}
  def validate(%__MODULE__{} = entry) do
    with {:ok, _value} <- Zoi.parse(@schema, entry),
         true <- (is_atom(entry.kind) and not is_nil(entry.kind)) or nonempty?(entry.kind),
         :ok <- Jido.PortableTerm.validate(entry.payload, :thread_entry_payload),
         :ok <- Jido.PortableTerm.validate(entry.refs, :thread_entry_refs) do
      {:ok, entry}
    else
      _other -> {:error, :invalid_entry}
    end
  end

  def validate(_value), do: {:error, :invalid_entry}

  @doc false
  @spec normalize(t() | map(), non_neg_integer(), integer()) :: t()
  def normalize(%__MODULE__{} = entry, seq, now) do
    %__MODULE__{
      id: entry.id || entry_id(),
      seq: seq,
      at: entry.at || now,
      kind: entry.kind || :note,
      payload: entry.payload || %{},
      refs: entry.refs || %{}
    }
    |> validate!()
  end

  def normalize(attrs, seq, now) when is_map(attrs) do
    %__MODULE__{
      id: field(attrs, :id) || entry_id(),
      seq: seq,
      at: field(attrs, :at) || now,
      kind: field(attrs, :kind) || :note,
      payload: field(attrs, :payload) || %{},
      refs: field(attrs, :refs) || %{}
    }
    |> validate!()
  end

  defp validate!(entry) do
    case validate(entry) do
      {:ok, valid} -> valid
      {:error, :invalid_entry} -> raise ArgumentError, "invalid thread entry"
    end
  end

  defp known_keys?(map, keys) do
    allowed = keys ++ Enum.map(keys, &String.to_atom/1)
    Map.keys(map) -- allowed == []
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp nonempty?(value), do: is_binary(value) and value != ""

  defp encode_kind(kind) when is_atom(kind),
    do: %{"type" => "atom", "value" => Atom.to_string(kind)}

  defp encode_kind(kind), do: %{"type" => "string", "value" => kind}
  defp decode_kind(kind) when is_atom(kind), do: kind

  defp decode_kind(%{"type" => "atom", "value" => kind}) when is_binary(kind) do
    String.to_existing_atom(kind)
  rescue
    ArgumentError -> nil
  end

  defp decode_kind(%{"type" => "string", "value" => kind}) when is_binary(kind), do: kind
  defp decode_kind(kind) when is_binary(kind), do: kind
  defp decode_kind(kind), do: kind
  defp entry_id, do: "entry_#{Jido.generate_id()}"
end

defimpl Runic.Identity.Projectable, for: Jido.Thread.Entry do
  def identity_document(entry), do: Jido.Thread.Entry.encode(entry)
end
