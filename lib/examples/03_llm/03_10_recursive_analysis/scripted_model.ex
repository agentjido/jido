defmodule Jido.Examples.RecursiveLanguageModel.Model do
  @moduledoc """
  Model adapter contract for the simulation.
  A request has a call ID, parent ID, corpus handle, range, depth, query, stage,
  and observation. Only a read observation contains corpus records.
  Decisions are `:read`, `:recurse` with child ranges, or `:answer` with counts.
  """

  @callback complete(term(), map()) :: {:ok, map()} | {:error, term()}
end

defmodule Jido.Examples.RecursiveLanguageModel.ScriptedModel do
  @moduledoc """
  A deterministic model that splits large ranges and counts failed jobs.
  `:chunk_size` controls leaf size. `:order` can be `:forward` or `:reverse`.
  `:overrides` maps `{offset, length, stage}` to a replacement adapter response.
  The call audit retains metadata only, so it does not retain the corpus.
  """

  use GenServer
  @behaviour Jido.Examples.RecursiveLanguageModel.Model

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def complete(server, request), do: GenServer.call(server, {:complete, request})

  def calls(server), do: GenServer.call(server, :calls)

  @impl true
  def init(opts) do
    chunk_size = Keyword.get(opts, :chunk_size, 64)
    order = Keyword.get(opts, :order, :forward)

    if is_integer(chunk_size) and chunk_size > 0 and order in [:forward, :reverse] do
      {:ok,
       %{
         chunk_size: chunk_size,
         order: order,
         overrides: Keyword.get(opts, :overrides, %{}),
         calls: []
       }}
    else
      {:stop, :invalid_model_options}
    end
  end

  @impl true
  def handle_call({:complete, request}, _from, state) do
    key = {request.range.offset, request.range.length, request.stage}
    reply = Map.get_lazy(state.overrides, key, fn -> {:ok, decide(request, state)} end)

    audit =
      request |> Map.drop([:observation]) |> Map.put(:records_received, records_received(request))

    {:reply, reply, %{state | calls: [audit | state.calls]}}
  end

  def handle_call(:calls, _from, state), do: {:reply, Enum.reverse(state.calls), state}

  defp decide(%{stage: :start, range: %{length: length} = range}, %{chunk_size: size} = state)
       when length > size do
    left_length = div(length, 2)
    left = %{offset: range.offset, length: left_length}
    right = %{offset: range.offset + left_length, length: length - left_length}
    ranges = if state.order == :reverse, do: [right, left], else: [left, right]
    %{op: :recurse, ranges: ranges}
  end

  defp decide(%{stage: :start}, _state), do: %{op: :read}

  defp decide(%{stage: :read, observation: records}, _state) do
    counts = records |> Enum.filter(&(&1.status == :failed)) |> Enum.frequencies_by(& &1.service)
    %{op: :answer, counts: counts}
  end

  defp decide(%{stage: :children, observation: children}, _state) do
    counts =
      Enum.reduce(children, %{}, fn child, acc ->
        Map.merge(acc, child.counts, fn _, a, b -> a + b end)
      end)

    %{op: :answer, counts: counts}
  end

  defp records_received(%{stage: :read, observation: records}), do: length(records)
  defp records_received(_request), do: 0
end
