defmodule Jido.Thread.EntryNormalizer do
  @moduledoc """
  Shared entry normalization for thread and storage append paths.

  Ensures all adapters apply the same defaults and attribute extraction for
  `%Jido.Thread.Entry{}` structs and plain maps.
  """

  alias Jido.Thread.Entry

  @type entry_input :: Entry.t() | map()
  @type opts :: [id_generator: (-> String.t())]

  @doc """
  Normalize a single entry input into `%Jido.Thread.Entry{}`.
  """
  @spec normalize(entry_input(), non_neg_integer(), integer(), opts()) :: Entry.t()
  def normalize(entry, seq, now, opts \\ [])

  def normalize(%Entry{} = entry, seq, now, opts) do
    id_generator = Keyword.get(opts, :id_generator, &generate_entry_id/0)

    %Entry{
      id: entry.id || id_generator.(),
      seq: seq,
      at: entry.at || now,
      kind: entry.kind || :note,
      payload: entry.payload || %{},
      refs: entry.refs || %{}
    }
  end

  def normalize(attrs, seq, now, opts) when is_map(attrs) do
    id_generator = Keyword.get(opts, :id_generator, &generate_entry_id/0)

    %Entry{
      id: fetch_entry_attr(attrs, :id, id_generator),
      seq: seq,
      at: fetch_entry_attr(attrs, :at, fn -> now end),
      kind: fetch_entry_attr(attrs, :kind, fn -> :note end),
      payload: fetch_entry_attr(attrs, :payload, fn -> %{} end),
      refs: fetch_entry_attr(attrs, :refs, fn -> %{} end)
    }
  end

  @doc """
  Normalize many entries, assigning monotonic sequence numbers from `base_seq`.
  """
  @spec normalize_many([entry_input()], non_neg_integer(), integer(), opts()) :: [Entry.t()]
  def normalize_many(entries, base_seq, now, opts \\ []) do
    entries
    |> Enum.with_index()
    |> Enum.map(fn {entry, idx} ->
      normalize(entry, base_seq + idx, now, opts)
    end)
  end

  defp fetch_entry_attr(attrs, key, default_fun) when is_function(default_fun, 0) do
    case Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key)) do
      nil -> default_fun.()
      value -> value
    end
  end

  defp generate_entry_id do
    "entry_" <> Jido.Util.generate_id()
  end
end
