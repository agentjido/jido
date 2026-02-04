defmodule Jido.Thread do
  @moduledoc """
  An append-only log of interaction entries.

  Thread is the canonical record of "what happened" in a conversation
  or workflow. It is provider-agnostic and never modified destructively.

  LLM context is derived from Thread via projection functions, not
  stored directly in Thread.

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

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(description: "Unique thread identifier"),
              rev:
                Zoi.integer(description: "Monotonic revision, increments on append")
                |> Zoi.default(0),
              entries:
                Zoi.list(Zoi.any(), description: "Ordered list of Entry structs")
                |> Zoi.default([]),
              created_at: Zoi.integer(description: "Creation timestamp (ms)"),
              updated_at: Zoi.integer(description: "Last update timestamp (ms)"),
              metadata: Zoi.map(description: "Arbitrary metadata") |> Zoi.default(%{}),
              stats: Zoi.map(description: "Cached aggregates") |> Zoi.default(%{entry_count: 0})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

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
  def append(%__MODULE__{} = thread, entries) do
    entries = List.wrap(entries)
    now = System.system_time(:millisecond)
    base_seq = length(thread.entries)

    prepared_entries =
      entries
      |> Enum.with_index()
      |> Enum.map(fn {entry, idx} ->
        prepare_entry(entry, base_seq + idx, now)
      end)

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
  @spec filter_by_kind(t(), atom() | [atom()]) :: [Entry.t()]
  def filter_by_kind(%__MODULE__{entries: entries}, kinds) when is_list(kinds) do
    Enum.filter(entries, &(&1.kind in kinds))
  end

  def filter_by_kind(thread, kind), do: filter_by_kind(thread, [kind])

  @doc "Get entries in seq range (inclusive)"
  @spec slice(t(), non_neg_integer(), non_neg_integer()) :: [Entry.t()]
  def slice(%__MODULE__{entries: entries}, from_seq, to_seq) do
    Enum.filter(entries, fn e -> e.seq >= from_seq and e.seq <= to_seq end)
  end

  defp prepare_entry(%Entry{} = entry, seq, now) do
    %{
      entry
      | id: entry.id || generate_entry_id(),
        seq: seq,
        at: entry.at || now
    }
  end

  defp prepare_entry(attrs, seq, now) when is_map(attrs) do
    %Entry{
      id: fetch_entry_attr(attrs, :id, &generate_entry_id/0),
      seq: seq,
      at: fetch_entry_attr(attrs, :at, fn -> now end),
      kind: fetch_entry_attr(attrs, :kind, fn -> :note end),
      payload: fetch_entry_attr(attrs, :payload, fn -> %{} end),
      refs: fetch_entry_attr(attrs, :refs, fn -> %{} end)
    }
  end

  defp fetch_entry_attr(attrs, key, default_fun) when is_function(default_fun, 0) do
    case Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key)) do
      nil -> default_fun.()
      value -> value
    end
  end

  defp generate_id do
    "thread_" <> Jido.Util.generate_id()
  end

  defp generate_entry_id do
    "entry_" <> Jido.Util.generate_id()
  end
end
