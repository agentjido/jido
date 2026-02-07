defmodule Jido.Thread.Store.Adapters.JournalBacked do
  @moduledoc """
  Thread persistence adapter backed by Jido.Signal.Journal.

  Stores thread entries as signals with type "jido.thread.entry".
  Thread ordering is by entry.seq (authoritative), not signal time.

  ## Mapping

  - `thread_id` → `signal.subject`
  - Each entry → Signal with type "jido.thread.entry"
  - `entry.seq` stored in signal.data for ordering (authoritative)

  ## Usage

      {:ok, store} = Jido.Thread.Store.new(Jido.Thread.Store.Adapters.JournalBacked)

      # With custom journal adapter
      {:ok, store} = Jido.Thread.Store.new(
        Jido.Thread.Store.Adapters.JournalBacked,
        journal_adapter: Jido.Signal.Journal.Adapters.ETS
      )
  """

  @behaviour Jido.Thread.Store

  alias Jido.Signal
  alias Jido.Signal.Journal
  alias Jido.Thread
  alias Jido.Thread.Entry

  @signal_type "jido.thread.entry"

  @impl true
  def init(opts) do
    adapter = Keyword.get(opts, :journal_adapter, Journal.Adapters.InMemory)
    journal = Journal.new(adapter)
    {:ok, %{journal: journal}}
  end

  @impl true
  def load(%{journal: journal} = state, thread_id) do
    signals = Journal.get_conversation(journal, thread_id)

    entries =
      signals
      |> Enum.filter(&(&1.type == @signal_type))
      |> Enum.map(&decode_entry/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.seq)

    case entries do
      [] ->
        {:error, state, :not_found}

      entries ->
        thread = reconstruct_thread(thread_id, entries)
        {:ok, state, thread}
    end
  end

  @impl true
  def save(%{journal: journal} = state, %Thread{} = thread) do
    result =
      thread.entries
      |> Enum.reduce_while({:ok, journal}, fn entry, {:ok, j} ->
        signal = encode_entry(thread.id, entry)

        case Journal.record(j, signal) do
          {:ok, j} -> {:cont, {:ok, j}}
          error -> {:halt, error}
        end
      end)

    case result do
      {:ok, journal} -> {:ok, %{state | journal: journal}}
      {:error, reason} -> {:error, state, reason}
    end
  end

  @impl true
  def append(%{journal: journal} = state, thread_id, entries) do
    {base_seq, existing_entries} = load_existing_entries(state, thread_id)
    now = System.system_time(:millisecond)
    prepared = prepare_entries(entries, base_seq, now)

    case record_entries(journal, thread_id, prepared) do
      {:ok, journal} ->
        thread = reconstruct_thread(thread_id, existing_entries ++ prepared)
        {:ok, %{state | journal: journal}, thread}

      {:error, reason} ->
        {:error, state, reason}
    end
  end

  defp load_existing_entries(state, thread_id) do
    case load(state, thread_id) do
      {:ok, _, thread} -> {length(thread.entries), thread.entries}
      {:error, _, :not_found} -> {0, []}
    end
  end

  defp prepare_entries(entries, base_seq, now) do
    entries
    |> Enum.with_index()
    |> Enum.map(fn {entry, idx} ->
      build_entry(entry, base_seq + idx, now)
    end)
  end

  defp record_entries(journal, thread_id, entries) do
    Enum.reduce_while(entries, {:ok, journal}, fn entry, {:ok, j} ->
      signal = encode_entry(thread_id, entry)

      case Journal.record(j, signal) do
        {:ok, j} -> {:cont, {:ok, j}}
        error -> {:halt, error}
      end
    end)
  end

  defp build_entry(entry, seq, now) do
    %Entry{
      id: get_entry_id(entry) || generate_id(),
      seq: seq,
      at: get_entry_at(entry) || now,
      kind: get_entry_kind(entry) || :note,
      payload: get_entry_payload(entry) || %{},
      refs: get_entry_refs(entry) || %{}
    }
  end

  defp get_entry_id(%Entry{id: id}), do: id
  defp get_entry_id(%{id: id}), do: id
  defp get_entry_id(_), do: nil

  defp get_entry_at(%Entry{at: at}), do: at
  defp get_entry_at(%{at: at}), do: at
  defp get_entry_at(_), do: nil

  defp get_entry_kind(%Entry{kind: kind}), do: kind
  defp get_entry_kind(%{kind: kind}), do: kind
  defp get_entry_kind(_), do: nil

  defp get_entry_payload(%Entry{payload: payload}), do: payload
  defp get_entry_payload(%{payload: payload}), do: payload
  defp get_entry_payload(_), do: nil

  defp get_entry_refs(%Entry{refs: refs}), do: refs
  defp get_entry_refs(%{refs: refs}), do: refs
  defp get_entry_refs(_), do: nil

  defp encode_entry(thread_id, %Entry{} = entry) do
    Signal.new!(%{
      id: "sig_#{entry.id}",
      type: @signal_type,
      source: "jido.thread",
      subject: thread_id,
      time: DateTime.utc_now() |> DateTime.to_iso8601(),
      data: %{
        entry_id: entry.id,
        seq: entry.seq,
        at: entry.at,
        kind: entry.kind,
        payload: entry.payload,
        refs: entry.refs
      }
    })
  end

  defp decode_entry(%Signal{data: data}) when is_map(data) do
    %Entry{
      id: data["entry_id"] || data[:entry_id],
      seq: data["seq"] || data[:seq],
      at: data["at"] || data[:at],
      kind: to_atom(data["kind"] || data[:kind]),
      payload: data["payload"] || data[:payload] || %{},
      refs: data["refs"] || data[:refs] || %{}
    }
  rescue
    _ -> nil
  end

  defp decode_entry(_), do: nil

  defp to_atom(atom) when is_atom(atom), do: atom

  defp to_atom(string) when is_binary(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError -> String.to_atom(string)
  end

  defp to_atom(_), do: :unknown

  defp reconstruct_thread(thread_id, entries) do
    timestamps = Enum.map(entries, & &1.at)
    now = System.system_time(:millisecond)

    %Thread{
      id: thread_id,
      rev: length(entries),
      entries: entries,
      created_at: Enum.min(timestamps, fn -> now end),
      updated_at: Enum.max(timestamps, fn -> now end),
      metadata: %{},
      stats: %{entry_count: length(entries)}
    }
  end

  defp generate_id, do: "entry_" <> random_string(12)

  defp random_string(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.url_encode64()
    |> binary_part(0, length)
  end
end
