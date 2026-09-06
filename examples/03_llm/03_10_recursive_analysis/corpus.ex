defmodule Jido.Examples.RecursiveLanguageModel.Store do
  @moduledoc """
  External corpus contract. A handle identifies an immutable corpus revision.
  A read must reject excess bytes before it returns records to the caller.
  Bytes are the sum of the sizes of records encoded with `:erlang.term_to_binary/1`.
  """

  @callback describe(term(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback read(term(), String.t(), map(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
end

defmodule Jido.Examples.RecursiveLanguageModel.Corpus do
  @moduledoc """
  An immutable local corpus store with an audit of read attempts.
  Tuples provide indexed reads. Prefix byte totals enforce the byte allowance
  before records leave the store. The audit contains metadata, not log contents.
  """

  use GenServer
  @behaviour Jido.Examples.RecursiveLanguageModel.Store

  def start_link(corpora), do: GenServer.start_link(__MODULE__, corpora)

  @impl true
  def describe(server, id), do: GenServer.call(server, {:describe, id})

  @impl true
  def read(server, id, range, allowance),
    do: GenServer.call(server, {:read, id, range, allowance})

  def reads(server), do: GenServer.call(server, :reads)

  @impl true
  def init(corpora) do
    indexed = Map.new(corpora, fn {id, records} -> {id, index(records)} end)
    {:ok, %{corpora: indexed, reads: []}}
  end

  @impl true
  def handle_call({:describe, id}, _from, state) do
    reply =
      with {:ok, corpus} <- fetch(state, id) do
        {:ok,
         %{
           records: tuple_size(corpus.records),
           bytes: elem(corpus.bytes, tuple_size(corpus.records))
         }}
      end

    {:reply, reply, state}
  end

  def handle_call({:read, id, range, allowance}, _from, state) do
    reply =
      with {:ok, corpus} <- fetch(state, id) do
        read_range(corpus, range, allowance)
      end

    audit = %{corpus_id: id, range: range, outcome: audit_outcome(reply)}
    {:reply, reply, %{state | reads: [audit | state.reads]}}
  end

  def handle_call(:reads, _from, state), do: {:reply, Enum.reverse(state.reads), state}

  defp index(records) do
    {_total, reversed} =
      Enum.reduce(records, {0, [0]}, fn record, {total, prefix} ->
        next = total + byte_size(:erlang.term_to_binary(record))
        {next, [next | prefix]}
      end)

    %{records: List.to_tuple(records), bytes: reversed |> Enum.reverse() |> List.to_tuple()}
  end

  defp fetch(state, id) do
    case Map.fetch(state.corpora, id) do
      {:ok, corpus} -> {:ok, corpus}
      :error -> {:error, :unknown_corpus}
    end
  end

  defp read_range(corpus, %{offset: offset, length: length}, allowance)
       when is_integer(offset) and offset >= 0 and is_integer(length) and length >= 0 and
              offset + length <= tuple_size(corpus.records) and is_integer(allowance) and
              allowance >= 0 do
    bytes = elem(corpus.bytes, offset + length) - elem(corpus.bytes, offset)

    if bytes <= allowance do
      records =
        if length == 0,
          do: [],
          else: Enum.map(offset..(offset + length - 1), &elem(corpus.records, &1))

      {:ok, %{records: records, bytes: bytes}}
    else
      {:error, {:byte_limit, bytes, allowance}}
    end
  end

  defp read_range(_corpus, _range, _allowance), do: {:error, :invalid_read}

  defp audit_outcome({:ok, %{bytes: bytes}}), do: {:ok, bytes}
  defp audit_outcome({:error, reason}), do: {:error, reason}
end
