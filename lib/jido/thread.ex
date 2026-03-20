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
  alias Jido.Thread.EntryNormalizer

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
              stats: Zoi.map(description: "Cached aggregates") |> Zoi.default(%{entry_count: 0}),
              pending_ref_updates:
                Zoi.map(description: "Internal ref updates awaiting checkpoint replay")
                |> Zoi.default(%{})
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
      stats: %{entry_count: 0},
      pending_ref_updates: %{}
    }
  end

  @doc "Append entries to thread (returns new thread)"
  @spec append(t(), Entry.t() | map() | [Entry.t() | map()]) :: t()
  def append(%__MODULE__{} = thread, entries) do
    entries = List.wrap(entries)
    now = System.system_time(:millisecond)
    base_seq = length(thread.entries)

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

  @doc "Merge additional refs into an entry identified by seq"
  @spec update_entry_refs(t(), non_neg_integer(), map()) :: t()
  def update_entry_refs(%__MODULE__{} = thread, seq, new_refs) when is_map(new_refs) do
    case merge_entry_refs(thread.entries, seq, new_refs) do
      {:ok, entries, true} ->
        pending_ref_updates =
          Map.update(thread.pending_ref_updates, seq, new_refs, &Map.merge(&1, new_refs))

        %{
          thread
          | entries: entries,
            updated_at: System.system_time(:millisecond),
            pending_ref_updates: pending_ref_updates
        }

      {:ok, _entries, false} ->
        thread

      {:error, :not_found} ->
        thread
    end
  end

  @doc false
  @spec checkpoint_overlay(t()) :: map() | nil
  def checkpoint_overlay(%__MODULE__{
        pending_ref_updates: pending_ref_updates,
        updated_at: updated_at
      })
      when map_size(pending_ref_updates) > 0 do
    %{ref_updates: pending_ref_updates, updated_at: updated_at}
  end

  def checkpoint_overlay(%__MODULE__{}), do: nil

  @doc false
  @spec apply_checkpoint_overlay(t(), map()) :: {:ok, t()} | {:error, term()}
  def apply_checkpoint_overlay(%__MODULE__{} = thread, overlay) when is_map(overlay) do
    with {:ok, ref_updates} <- overlay_ref_updates(overlay),
         {:ok, overlay_updated_at} <- overlay_updated_at(overlay, thread.updated_at) do
      Enum.reduce_while(ref_updates, {:ok, thread}, fn {raw_seq, refs}, {:ok, acc} ->
        with {:ok, seq} <- normalize_overlay_seq(raw_seq),
             {:ok, entries, _changed?} <- merge_entry_refs(acc.entries, seq, refs) do
          pending_ref_updates =
            Map.update(acc.pending_ref_updates, seq, refs, &Map.merge(&1, refs))

          updated_thread = %{acc | entries: entries, pending_ref_updates: pending_ref_updates}
          {:cont, {:ok, updated_thread}}
        else
          {:error, :not_found} -> {:halt, {:error, {:missing_entry, raw_seq}}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, updated_thread} ->
          {:ok,
           %{updated_thread | updated_at: max(updated_thread.updated_at, overlay_updated_at)}}

        {:error, _reason} = error ->
          error
      end
    end
  end

  def apply_checkpoint_overlay(%__MODULE__{}, _overlay), do: {:error, :invalid_overlay}

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

  defp generate_id do
    "thread_" <> Jido.Util.generate_id()
  end

  defp merge_entry_refs(entries, seq, new_refs) when is_integer(seq) and is_map(new_refs) do
    {entries, {found?, changed?}} =
      Enum.map_reduce(entries, {false, false}, fn
        %{seq: ^seq} = entry, {_found?, changed?} ->
          merged_refs = Map.merge(entry.refs, new_refs)

          updated_entry =
            if merged_refs == entry.refs, do: entry, else: %{entry | refs: merged_refs}

          {updated_entry, {true, changed? or updated_entry != entry}}

        entry, acc ->
          {entry, acc}
      end)

    if found? do
      {:ok, entries, changed?}
    else
      {:error, :not_found}
    end
  end

  defp merge_entry_refs(_entries, _seq, _new_refs), do: {:error, :invalid_overlay_refs}

  defp normalize_overlay_seq(seq) when is_integer(seq) and seq >= 0, do: {:ok, seq}

  defp normalize_overlay_seq(seq) when is_binary(seq) do
    case Integer.parse(seq) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _ -> {:error, :invalid_overlay_seq}
    end
  end

  defp normalize_overlay_seq(_seq), do: {:error, :invalid_overlay_seq}

  defp overlay_ref_updates(overlay) do
    case Map.get(overlay, :ref_updates) || Map.get(overlay, "ref_updates") || %{} do
      ref_updates when is_map(ref_updates) -> {:ok, ref_updates}
      _ -> {:error, :invalid_overlay_ref_updates}
    end
  end

  defp overlay_updated_at(overlay, default) do
    case Map.get(overlay, :updated_at) || Map.get(overlay, "updated_at") || default do
      updated_at when is_integer(updated_at) -> {:ok, updated_at}
      _ -> {:error, :invalid_overlay_updated_at}
    end
  end
end
