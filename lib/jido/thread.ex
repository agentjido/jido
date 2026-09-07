defmodule Jido.Thread do
  @moduledoc """
  An optional append-only value for interaction entries.

  Applications can store a Thread in an Agent schema and return its complete
  next value as ordinary Agent state. The application owns its history format,
  retention, and model-context projection. A list of message maps is sufficient
  when entry identity, timestamps, and references are not needed.

  Thread has no Plugin, runtime process, or automatic message capture. Its
  append API returns a new value; it does not commit Agent state. Convenience
  constructors and append can read the clock and generate missing identifiers.

  ## Example

      thread = Thread.new(metadata: %{user_id: "u1"})

      thread = Thread.append(thread, %{
        kind: :message,
        payload: %{role: "user", content: "Hello"}
      })

      Thread.entry_count(thread)  # => 1
      Thread.last(thread).kind    # => :message
  """

  alias Jido.Thread.Entry
  alias Jido.Thread.EntryNormalizer

  @stats_schema Zoi.object(
                  %{
                    entry_count:
                      Zoi.integer(description: "Number of retained entries") |> Zoi.min(0)
                  },
                  unrecognized_keys: :preserve
                )

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(description: "Unique thread identifier") |> Zoi.min(1),
              rev:
                Zoi.integer(description: "Next monotonic entry sequence")
                |> Zoi.min(0)
                |> Zoi.default(0),
              entries:
                Zoi.list(Entry.schema(), description: "Ordered list of Entry structs")
                |> Zoi.default([]),
              created_at: Zoi.integer(description: "Creation timestamp (ms)"),
              updated_at: Zoi.integer(description: "Last update timestamp (ms)"),
              metadata: Zoi.map(description: "Arbitrary metadata") |> Zoi.default(%{}),
              stats: Zoi.default(@stats_schema, %{entry_count: 0})
            },
            coerce: true
          )
          |> Zoi.refine({__MODULE__, :validate_invariants, []})

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the data schema for a Thread."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Create a new empty thread"
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    now = opts[:now] || System.system_time(:millisecond)

    %__MODULE__{
      id: opts[:id] || generate_id(),
      rev: 0,
      entries: [],
      created_at: now,
      updated_at: now,
      metadata: opts[:metadata] || %{},
      stats: %{entry_count: 0}
    }
  end

  @doc "Append entries to thread (returns new thread)"
  @spec append(t(), Entry.t() | map() | [Entry.t() | map()]) :: t()
  def append(%__MODULE__{} = thread, entries) when entries in [nil, []], do: thread

  def append(%__MODULE__{} = thread, entries) do
    entries = List.wrap(entries)
    now = System.system_time(:millisecond)
    base_seq = thread.rev

    prepared_entries =
      EntryNormalizer.normalize_many(entries, base_seq, now)

    %{
      thread
      | entries: thread.entries ++ prepared_entries,
        rev: thread.rev + length(prepared_entries),
        updated_at: now,
        stats: %{thread.stats | entry_count: thread.stats.entry_count + length(prepared_entries)}
    }
  end

  @doc "Get entry count"
  @spec entry_count(t()) :: non_neg_integer()
  def entry_count(%__MODULE__{stats: %{entry_count: count}}), do: count

  @doc "Get last entry"
  @spec last(t()) :: Entry.t() | nil
  def last(%__MODULE__{entries: []}), do: nil
  def last(%__MODULE__{entries: entries}), do: List.last(entries)

  @doc "Get entry by seq"
  @spec get_entry(t(), non_neg_integer()) :: Entry.t() | nil
  def get_entry(%__MODULE__{entries: entries}, seq) do
    Enum.find(entries, &(&1.seq == seq))
  end

  @doc "Get all entries as list"
  @spec to_list(t()) :: [Entry.t()]
  def to_list(%__MODULE__{entries: entries}), do: entries

  @doc "Filter entries by kind"
  @spec filter_by_kind(t() | nil, atom() | [atom()]) :: [Entry.t()]
  def filter_by_kind(%__MODULE__{entries: entries}, kinds) when is_list(kinds) do
    Enum.filter(entries, &(&1.kind in kinds))
  end

  def filter_by_kind(nil, _kinds), do: []

  def filter_by_kind(%__MODULE__{entries: entries}, kind) when is_atom(kind) do
    Enum.filter(entries, &(&1.kind === kind))
  end

  @doc "Get entries in seq range (inclusive)"
  @spec slice(t(), non_neg_integer(), non_neg_integer()) :: [Entry.t()]
  def slice(%__MODULE__{entries: entries}, from_seq, to_seq) do
    Enum.filter(entries, fn e -> e.seq >= from_seq and e.seq <= to_seq end)
  end

  @doc false
  def validate_invariants(%__MODULE__{} = thread, opts) do
    count = length(thread.entries)
    ids = Enum.map(thread.entries, & &1.id)
    sequences = Enum.map(thread.entries, & &1.seq)

    cond do
      unrelated_struct?(opts) ->
        {:error, "Thread schema does not accept unrelated structs"}

      thread.stats.entry_count != count ->
        {:error, "entry_count must equal the number of retained entries"}

      length(Enum.uniq(ids)) != count ->
        {:error, "entry IDs must be unique"}

      sequences != retained_sequences(thread.rev, count) ->
        {:error, "entry sequences must be the ordered suffix before the revision"}

      true ->
        :ok
    end
  end

  defp retained_sequences(_rev, 0), do: []

  defp retained_sequences(rev, count) when rev >= count,
    do: Enum.to_list((rev - count)..(rev - 1))

  defp retained_sequences(_rev, _count), do: :invalid

  defp unrelated_struct?(opts) do
    case get_in(opts, [:ctx, Access.key(:input)]) do
      %__MODULE__{} -> false
      input when is_struct(input) -> true
      _input -> false
    end
  end

  defp generate_id do
    "thread_" <> Jido.Util.generate_id()
  end
end
