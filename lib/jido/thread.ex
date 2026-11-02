defmodule Jido.Thread do
  @moduledoc """
  A portable append-only interaction log.

  A Thread is an immutable value. It does not own a process or a persistence
  adapter.
  """

  alias __MODULE__.Entry

  @version 1
  @schema Zoi.struct(
            __MODULE__,
            %{
              version: Zoi.integer() |> Zoi.default(@version),
              id: Zoi.string() |> Zoi.min(1),
              rev: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0),
              entries: Zoi.list(Entry.schema()) |> Zoi.default([]),
              created_at: Zoi.integer(),
              updated_at: Zoi.integer(),
              metadata: Zoi.map() |> Zoi.default(%{}),
              stats: Zoi.map() |> Zoi.default(%{entry_count: 0})
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Thread schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates an empty Thread."
  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    now = Keyword.get(opts, :now, System.system_time(:millisecond))

    %__MODULE__{
      version: @version,
      id: Keyword.get(opts, :id, "thread_#{Jido.generate_id()}"),
      rev: 0,
      entries: [],
      created_at: now,
      updated_at: now,
      metadata: Keyword.get(opts, :metadata, %{}),
      stats: %{entry_count: 0}
    }
    |> validate!()
  end

  @doc "Appends entries and returns the complete next Thread."
  @spec append(t(), Entry.t() | map() | [Entry.t() | map()] | nil) :: t()
  def append(%__MODULE__{} = thread, entries) when entries in [nil, []], do: thread

  def append(%__MODULE__{} = thread, entries) do
    now = max(System.system_time(:millisecond), thread.updated_at)
    base_seq = length(thread.entries)

    appended =
      entries
      |> List.wrap()
      |> Enum.with_index(base_seq)
      |> Enum.map(fn {entry, seq} -> Entry.normalize(entry, seq, now) end)

    count = length(appended)

    %{
      thread
      | entries: thread.entries ++ appended,
        rev: thread.rev + count,
        updated_at: now,
        stats: %{entry_count: thread.stats.entry_count + count}
    }
    |> validate!()
  end

  @doc "Returns the number of entries."
  @spec entry_count(t()) :: non_neg_integer()
  def entry_count(%__MODULE__{stats: %{entry_count: count}}), do: count

  @doc "Returns the last entry or nil."
  @spec last(t()) :: Entry.t() | nil
  def last(%__MODULE__{entries: []}), do: nil
  def last(%__MODULE__{entries: entries}), do: List.last(entries)

  @doc "Returns one entry by its sequence number."
  @spec get_entry(t(), non_neg_integer()) :: Entry.t() | nil
  def get_entry(%__MODULE__{entries: entries}, seq), do: Enum.find(entries, &(&1.seq == seq))

  @doc "Returns entries in chronological order."
  @spec to_list(t()) :: [Entry.t()]
  def to_list(%__MODULE__{entries: entries}), do: entries

  @doc "Returns entries with one of the selected kinds."
  @spec filter_by_kind(t() | nil, Entry.kind() | [Entry.kind()]) :: [Entry.t()]
  def filter_by_kind(nil, _kind), do: []

  def filter_by_kind(%__MODULE__{entries: entries}, kinds) when is_list(kinds),
    do: Enum.filter(entries, &(&1.kind in kinds))

  def filter_by_kind(%__MODULE__{entries: entries}, kind)
      when is_atom(kind) or is_binary(kind),
      do: Enum.filter(entries, &(&1.kind == kind))

  @doc "Returns entries in an inclusive sequence range."
  @spec slice(t(), non_neg_integer(), non_neg_integer()) :: [Entry.t()]
  def slice(%__MODULE__{entries: entries}, from_seq, to_seq)
      when is_integer(from_seq) and from_seq >= 0 and is_integer(to_seq) and to_seq >= from_seq,
      do: Enum.filter(entries, &(&1.seq >= from_seq and &1.seq <= to_seq))

  @doc "Returns a versioned portable map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = thread) do
    validate!(thread)

    %{
      "type" => "jido.thread",
      "version" => @version,
      "id" => thread.id,
      "rev" => thread.rev,
      "entries" => Enum.map(thread.entries, &Entry.encode/1),
      "created_at" => thread.created_at,
      "updated_at" => thread.updated_at,
      "metadata" => thread.metadata
    }
  end

  @doc "Decodes and validates a portable Thread map."
  @spec decode(t() | map()) :: {:ok, t()} | {:error, :invalid_thread | :unsupported_version}
  def decode(%__MODULE__{} = thread), do: validate(thread)

  def decode(map) when is_map(map) do
    with :ok <- document_version(map),
         true <- known_keys?(map),
         {:ok, entries} <- decode_entries(field(map, :entries) || []),
         thread = %__MODULE__{
           version: @version,
           id: field(map, :id),
           rev: field(map, :rev) || length(entries),
           entries: entries,
           created_at: field(map, :created_at),
           updated_at: field(map, :updated_at),
           metadata: field(map, :metadata) || %{},
           stats: %{entry_count: length(entries)}
         },
         {:ok, thread} <- validate(thread) do
      {:ok, thread}
    else
      {:error, :unsupported_version} = error -> error
      _other -> {:error, :invalid_thread}
    end
  end

  def decode(_value), do: {:error, :invalid_thread}

  @doc false
  @spec validate(t()) :: {:ok, t()} | {:error, :invalid_thread}
  def validate(%__MODULE__{} = thread) do
    valid_entries? =
      is_list(thread.entries) and
        Enum.all?(Enum.with_index(thread.entries), fn {entry, index} ->
          match?({:ok, _value}, Entry.validate(entry)) and entry.seq == index
        end)

    with {:ok, _value} <- Zoi.parse(@schema, thread),
         true <- thread.version == @version,
         true <- thread.rev == length(thread.entries),
         true <- thread.stats == %{entry_count: length(thread.entries)},
         true <- thread.updated_at >= thread.created_at,
         true <- valid_entries?,
         :ok <- Jido.PortableTerm.validate(thread.metadata, :thread_metadata) do
      {:ok, thread}
    else
      _other -> {:error, :invalid_thread}
    end
  end

  def validate(_value), do: {:error, :invalid_thread}

  defp validate!(thread) do
    case validate(thread) do
      {:ok, valid} -> valid
      {:error, :invalid_thread} -> raise ArgumentError, "invalid thread"
    end
  end

  defp decode_entries(entries) when is_list(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, decoded} ->
      case Entry.decode(entry) do
        {:ok, value} -> {:cont, {:ok, [value | decoded]}}
        {:error, _reason} -> {:halt, {:error, :invalid_thread}}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      error -> error
    end
  end

  defp decode_entries(_entries), do: {:error, :invalid_thread}

  defp document_version(map) do
    case {field(map, :type), field(map, :version)} do
      {"jido.thread", @version} -> :ok
      _other -> {:error, :unsupported_version}
    end
  end

  defp known_keys?(map) do
    keys = ~w(type version id rev entries created_at updated_at metadata stats __struct__)
    allowed = keys ++ Enum.map(keys, &String.to_atom/1)
    Map.keys(map) -- allowed == []
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end

defimpl Runic.Identity.Projectable, for: Jido.Thread do
  def identity_document(thread), do: Jido.Thread.encode(thread)
end
