defmodule Jido.Examples.RecursiveLanguageModel.Runner do
  @moduledoc """
  Executes model decisions with one shared budget for the complete call tree.
  Every split must partition its parent into smaller, nonempty ranges. A model
  can answer only after a read or child reduction, and its counts must agree
  with that evidence. Only metadata and counts enter the returned Agent state.
  """

  alias Jido.Action.Error
  alias Jido.Examples.RecursiveLanguageModel.Contracts

  def run(input, context) do
    with {:ok, input} <- parse(Contracts.request(), input, :invalid_request),
         {:ok, clients} <-
           parse(Contracts.clients(), Map.take(context, [:model, :store]), :invalid_clients),
         {:ok, info} <- invoke(clients.store, :describe, [input.corpus_id]),
         :ok <- valid_info(info),
         range = input.range || %{offset: 0, length: info.records},
         :ok <- within_corpus(range, info.records),
         {:ok, counts, _id, state} <- enter(range, 0, 0, initial(input, clients)) do
      {:ok,
       %{
         corpus_id: input.corpus_id,
         counts: counts,
         source_ranges: Enum.sort_by(state.ranges, & &1.offset),
         call_tree: Enum.sort_by(state.tree, & &1.id),
         usage: usage(state)
       }}
    end
  end

  defp initial(input, clients) do
    Map.merge(clients, %{
      corpus_id: input.corpus_id,
      query: input.query,
      limits: input.limits,
      calls: 0,
      steps: 0,
      bytes_read: 0,
      records_read: 0,
      max_depth: 0,
      peak_read_records: 0,
      ranges: [],
      tree: []
    })
  end

  defp enter(range, depth, parent_id, state) do
    with :ok <- budget(state, :max_depth, depth),
         :ok <- budget(state, :max_calls, state.calls + 1) do
      call = %{id: state.calls + 1, parent_id: parent_id, range: range, depth: depth}
      next = %{state | calls: call.id, max_depth: max(state.max_depth, depth)}
      step(call, :start, nil, next)
    end
  end

  defp step(call, stage, observation, state) do
    with :ok <- budget(state, :max_steps, state.steps + 1) do
      next = %{state | steps: state.steps + 1}

      request =
        Map.merge(call, %{
          corpus_id: state.corpus_id,
          query: state.query,
          stage: stage,
          observation: observation
        })

      with {:ok, raw} <- invoke(state.model, :complete, [request]),
           {:ok, decision} <- parse(Contracts.decision(), raw, :invalid_decision) do
        execute(decision, call, stage, observation, next)
      end
    end
  end

  defp execute(%{op: :read}, call, :start, _observation, state) do
    with :ok <- budget(state, :max_read_records, call.range.length),
         {:ok, payload} <- read(call.range, state),
         {:ok, records} <- validate_read(payload, call.range, state) do
      next = %{
        state
        | bytes_read: state.bytes_read + payload.bytes,
          records_read: state.records_read + length(records),
          peak_read_records: max(state.peak_read_records, length(records)),
          ranges: [call.range | state.ranges]
      }

      step(call, :read, records, next)
    end
  end

  defp execute(%{op: :recurse, ranges: ranges}, call, :start, _observation, state) do
    with :ok <- partition(ranges, call.range),
         :ok <- budget(state, :max_depth, call.depth + 1),
         :ok <- budget(state, :max_calls, state.calls + length(ranges)),
         {:ok, children, next} <- children(ranges, call, state) do
      step(call, :children, children, next)
    end
  end

  defp execute(%{op: :answer, counts: counts}, call, stage, observation, state)
       when stage in [:read, :children] do
    if counts == expected_counts(stage, observation) do
      node = Map.put(call, :counts, counts)
      {:ok, counts, call.id, %{state | tree: [node | state.tree]}}
    else
      failure(:unsupported_answer, %{call_id: call.id})
    end
  end

  defp execute(decision, call, stage, _observation, _state) do
    failure(:invalid_transition, %{call_id: call.id, stage: stage, op: decision.op})
  end

  defp children(ranges, call, state) do
    Enum.reduce_while(ranges, {:ok, [], state}, fn range, {:ok, results, current} ->
      case enter(range, call.depth + 1, call.id, current) do
        {:ok, counts, id, next} ->
          {:cont, {:ok, [%{id: id, range: range, counts: counts} | results], next}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, results, next} -> {:ok, Enum.sort_by(results, & &1.range.offset), next}
      error -> error
    end
  end

  defp partition(ranges, parent) do
    sorted = Enum.sort_by(ranges, & &1.offset)

    end_offset =
      Enum.reduce_while(sorted, parent.offset, fn range, offset ->
        if range.offset == offset and range.length > 0 and range.length < parent.length do
          {:cont, offset + range.length}
        else
          {:halt, :invalid}
        end
      end)

    if length(ranges) >= 2 and end_offset == parent.offset + parent.length,
      do: :ok,
      else: failure(:invalid_partition)
  end

  defp read(range, state) do
    allowance = state.limits.max_bytes - state.bytes_read

    case invoke(state.store, :read, [state.corpus_id, range, allowance]) do
      {:error, %Error.ExecutionFailureError{details: %{reason: {:byte_limit, bytes, _}}}}
      when is_integer(bytes) and bytes > allowance ->
        budget(state, :max_bytes, state.bytes_read + bytes)

      result ->
        result
    end
  end

  defp validate_read(%{records: records, bytes: bytes}, range, state)
       when is_list(records) and is_integer(bytes) and bytes >= 0 do
    actual_bytes =
      Enum.reduce(records, 0, fn record, total ->
        total + byte_size(:erlang.term_to_binary(record))
      end)

    cond do
      length(records) != range.length or bytes != actual_bytes -> failure(:invalid_read)
      state.bytes_read + bytes > state.limits.max_bytes -> failure(:invalid_read)
      true -> parse(Zoi.list(Contracts.record()), records, :invalid_records)
    end
  end

  defp validate_read(_payload, _range, _state), do: failure(:invalid_read)

  defp expected_counts(:read, records) do
    Enum.reduce(records, %{}, fn
      %{status: :failed, service: service}, counts -> Map.update(counts, service, 1, &(&1 + 1))
      _record, counts -> counts
    end)
  end

  defp expected_counts(:children, children) do
    Enum.reduce(children, %{}, fn child, counts ->
      Map.merge(counts, child.counts, fn _service, a, b -> a + b end)
    end)
  end

  defp valid_info(%{records: records, bytes: bytes})
       when is_integer(records) and records >= 0 and is_integer(bytes) and bytes >= 0,
       do: :ok

  defp valid_info(_info), do: failure(:invalid_corpus_info)

  defp within_corpus(range, count) do
    if range.offset + range.length <= count, do: :ok, else: failure(:range_outside_corpus)
  end

  defp budget(state, limit, requested) do
    if requested <= Map.fetch!(state.limits, limit) do
      :ok
    else
      failure(:budget_exhausted, %{
        limit: limit,
        requested: requested,
        maximum: Map.fetch!(state.limits, limit),
        usage: usage(state)
      })
    end
  end

  defp usage(state),
    do:
      Map.take(state, [:calls, :steps, :bytes_read, :records_read, :max_depth, :peak_read_records])

  defp parse(schema, value, code) do
    case Zoi.parse(schema, value) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _issues} -> failure(code)
    end
  end

  defp invoke({module, client}, operation, args) do
    case apply(module, operation, [client | args]) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> failure(:adapter_error, %{operation: operation, reason: reason})
      _other -> failure(:invalid_adapter_response, %{operation: operation})
    end
  rescue
    error -> failure(:adapter_error, %{operation: operation, reason: error.__struct__})
  catch
    kind, reason -> failure(:adapter_error, %{operation: operation, reason: {kind, reason}})
  end

  defp failure(code, details \\ %{}),
    do: {:error, Error.execution_error("RLM simulation failed", Map.put(details, :code, code))}
end
