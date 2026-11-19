defmodule Jido.Thread do
  alias Jido.Joi

  @moduledoc """
  A portable append-only Agent Thread.

  A Thread is an immutable value. It does not own a process or a persistence
  adapter. Feature layers can project its entries for their own use.
  """

  alias __MODULE__.{Document, Entry}

  @version 1
  @field_aliases Document.aliases([
                   :type,
                   :version,
                   :id,
                   :rev,
                   :entries,
                   :created_at,
                   :updated_at,
                   :metadata,
                   :stats,
                   :__struct__
                 ])
  @schema Joi.struct(
            __MODULE__,
            %{
              version: Joi.integer() |> Joi.default(@version),
              id: Joi.string() |> Joi.min(1),
              rev: Joi.integer() |> Joi.min(0) |> Joi.default(0),
              entries: Joi.list(Entry.schema()) |> Joi.default([]),
              created_at: Joi.integer(),
              updated_at: Joi.integer(),
              metadata: Joi.map() |> Joi.default(%{}),
              stats: Joi.map() |> Joi.default(%{entry_count: 0})
            },
            unrecognized_keys: :error
          )

  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  @doc "Returns the Thread schema."
  @spec schema() :: Joi.schema()
  def schema, do: @schema

  @doc "Creates an empty Thread."
  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    now = Keyword.get(opts, :now, System.system_time(:millisecond))

    %__MODULE__{
      version: @version,
      id: Keyword.get(opts, :id, "thread_#{Jido.Id.uuid7()}"),
      rev: 0,
      entries: [],
      created_at: now,
      updated_at: now,
      metadata: Keyword.get(opts, :metadata, %{}),
      stats: %{entry_count: 0}
    }
    |> validate()
    |> unwrap!()
  end

  @doc "Appends entries and returns the complete next Thread."
  @spec append(t(), Entry.t() | map() | [Entry.t() | map()] | nil) :: t()
  def append(%__MODULE__{} = thread, entries) when entries in [nil, []], do: thread

  def append(%__MODULE__{} = thread, entries) do
    now = max(System.system_time(:millisecond), thread.updated_at)

    with {:ok, [], base_seq} <- scan_entries(thread.entries, &validate_entry/3) do
      {appended, next_seq} =
        entries
        |> List.wrap()
        |> Enum.map_reduce(base_seq, fn entry, seq -> {Entry.normalize(entry, seq, now), seq + 1} end)

      added = next_seq - base_seq

      updated = %{
        thread
        | entries: thread.entries ++ appended,
          rev: thread.rev + added,
          updated_at: now,
          stats: %{entry_count: thread.stats.entry_count + added}
      }

      validate_header(updated, next_seq)
    end
    |> unwrap!()
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

  @doc "Returns entries in append order, from the lowest sequence number to the highest."
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
  def encode(%__MODULE__{entries: entries} = thread) do
    with {:ok, encoded, count} <- scan_entries(entries, &encode_entry/3),
         {:ok, thread} <- validate_header(thread, count) do
      {:ok,
       %{
         "type" => "jido.thread",
         "version" => @version,
         "id" => thread.id,
         "rev" => thread.rev,
         "entries" => encoded,
         "created_at" => thread.created_at,
         "updated_at" => thread.updated_at,
         "metadata" => thread.metadata
       }}
    end
    |> unwrap!()
  end

  @doc "Decodes and validates a portable Thread map."
  @spec decode(t() | map()) :: {:ok, t()} | {:error, :invalid_thread | :unsupported_version}
  def decode(%__MODULE__{} = thread), do: validate(thread)

  def decode(map) when is_map(map) do
    with :ok <- document_version(map),
         {:ok, fields} <- Document.normalize_fields(map, @field_aliases),
         {:ok, entries, count} <- scan_entries(Document.default(fields[:entries], []), &decode_entry/3),
         thread = %__MODULE__{
           version: @version,
           id: fields[:id],
           rev: Document.default(fields[:rev], count),
           entries: entries,
           created_at: fields[:created_at],
           updated_at: fields[:updated_at],
           metadata: Document.default(fields[:metadata], %{}),
           stats: %{entry_count: count}
         } do
      validate_header(thread, count)
    else
      {:error, :unsupported_version} = error -> error
      _other -> {:error, :invalid_thread}
    end
  end

  def decode(_value), do: {:error, :invalid_thread}

  @doc false
  @spec validate(t()) :: {:ok, t()} | {:error, :invalid_thread}
  def validate(%__MODULE__{entries: entries} = thread) do
    with {:ok, [], count} <- scan_entries(entries, &validate_entry/3),
         do: validate_header(thread, count)
  end

  def validate(_value), do: {:error, :invalid_thread}

  defp validate_header(thread, count) do
    # The entry scan already checked the list and every Entry.
    with :ok <- Joi.validate(@schema, %{thread | entries: []}),
         true <- thread.version == @version,
         true <- thread.rev == count,
         true <- thread.stats == %{entry_count: count},
         true <- thread.updated_at >= thread.created_at,
         :ok <- Jido.Codec.Term.validate(thread.metadata, :thread_metadata) do
      {:ok, thread}
    else
      _other -> {:error, :invalid_thread}
    end
  end

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, :invalid_thread}), do: raise(ArgumentError, "invalid thread")

  defp scan_entries(entries, step), do: scan_entries(entries, step, 0, [])

  defp scan_entries([], _step, seq, acc), do: {:ok, Enum.reverse(acc), seq}

  defp scan_entries([entry | tail], step, seq, acc) do
    case step.(entry, seq, acc) do
      {:ok, acc} -> scan_entries(tail, step, seq + 1, acc)
      _invalid -> {:error, :invalid_thread}
    end
  end

  defp scan_entries(_improper, _step, _seq, _acc), do: {:error, :invalid_thread}

  defp validate_entry(%Entry{seq: seq} = entry, seq, acc) do
    with {:ok, _entry} <- Entry.validate(entry),
         do: {:ok, acc}
  end

  defp validate_entry(_entry, _seq, _acc), do: :error

  defp encode_entry(%Entry{seq: seq} = entry, seq, acc) do
    with {:ok, document} <- Entry.encode_document(entry),
         do: {:ok, [document | acc]}
  end

  defp encode_entry(_entry, _seq, _acc), do: :error

  defp decode_entry(document, seq, acc) do
    case Entry.decode(document) do
      {:ok, %Entry{seq: ^seq} = entry} -> {:ok, [entry | acc]}
      _invalid -> :error
    end
  end

  defp document_version(map)
       when (is_map_key(map, :type) and is_map_key(map, "type")) or
              (is_map_key(map, :version) and is_map_key(map, "version")),
       do: {:error, :invalid_thread}

  defp document_version(map) do
    case {Document.field(map, :type), Document.field(map, :version)} do
      {"jido.thread", @version} -> :ok
      _other -> {:error, :unsupported_version}
    end
  end
end

defimpl Runic.Identity.Projectable, for: Jido.Thread do
  def identity_document(thread), do: Jido.Thread.encode(thread)
end
