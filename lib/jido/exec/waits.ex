defmodule Jido.Exec.Waits do
  @moduledoc """
  Flow wait operations for execution hosts.

  The host supplies a clock and accepted event candidates. This module inspects
  requests and applies one wait result through native Runic events. Resolution
  runs no Actions or hooks. Save the result before resuming execution.

  The host owns input admission, duplicate detection, clock policy, retention,
  storage, and Worker control. Runtime context must be supplied after restore.
  """

  alias Jido.Exec.Frame
  alias Runic.Workflow
  alias Runic.Workflow.{Fact, Invokable, Runnable}
  alias Runic.Workflow.Events.{ActivationConsumed, FactProduced}

  @typedoc "A host clock, read when each wait opens, in UTC Unix milliseconds."
  @type clock :: non_neg_integer() | (-> non_neg_integer())
  @typedoc "One resolved timer or event option."
  @type option :: %{
          name: String.t(),
          event: String.t() | nil,
          match: map(),
          deadline: non_neg_integer() | nil
        }
  @typedoc "An open wait with an opaque ID scoped to its host execution."
  @type request :: %{
          id: String.t(),
          execution_id: term(),
          path: [String.t()],
          options: [option()],
          opened_at: non_neg_integer()
        }
  @typedoc "An accepted event and its host-assigned time and stable receipt order."
  @type candidate :: %{
          input: %{
            required(:id) => term(),
            required(:event) => String.t(),
            required(:payload) => map()
          },
          accepted_at: non_neg_integer(),
          order: non_neg_integer()
        }

  @doc "Adds wait support without changing the host's output validation policy."
  @spec context(map(), term(), clock()) :: map()
  def context(context, execution_id, clock) when is_map(context) do
    Map.put(context, :__jido_wait_host__, %{execution_id: execution_id, clock: clock})
  end

  @doc "Lists open requests in stable path and occurrence order."
  @spec pending(Workflow.t()) :: [request()]
  def pending(workflow) do
    closed = MapSet.new(records(workflow, :jido_wait_resolution), & &1.wait_id)

    workflow
    |> records(:jido_wait_request)
    |> Enum.reject(&MapSet.member?(closed, &1.id))
    |> Enum.sort_by(&{&1.path, &1.id})
    |> Enum.map(&Map.take(&1, [:id, :execution_id, :path, :options, :opened_at]))
  end

  @doc "Returns the earliest open timer deadline, or nil."
  @spec next_deadline(Workflow.t()) :: non_neg_integer() | nil
  def next_deadline(workflow) do
    for request <- pending(workflow),
        option <- request.options,
        is_integer(option.deadline),
        reduce: nil do
      nil -> option.deadline
      deadline -> min(deadline, option.deadline)
    end
  end

  @doc "Checks an event name and payload against the request's event options."
  @spec matches?(request(), String.t(), map()) :: boolean()
  def matches?(request, event, payload) when is_binary(event) and is_map(payload),
    do: Enum.any?(request.options, &matches_option?(&1, event, payload))

  @doc """
  Resolves one occurrence from host candidates and due timers.

  Supply candidates addressed to this occurrence only. The earliest acceptance
  or deadline wins. Timers win exact-time ties; receipt order and option order
  break other ties. Future candidates are ignored. With no eligible candidate
  or timer, the workflow is unchanged. Repeating a closed resolution is inert.
  """
  @spec resolve(Workflow.t(), String.t(), [candidate()], non_neg_integer()) ::
          {:ok, Workflow.t()} | {:error, Exception.t()}
  def resolve(workflow, wait_id, candidates, now) when is_integer(now) and now >= 0 do
    with :ok <- validate_candidates(candidates) do
      requests = records(workflow, :jido_wait_request)
      closed = records(workflow, :jido_wait_resolution)

      cond do
        Enum.any?(closed, &(&1.wait_id == wait_id)) ->
          {:ok, workflow}

        request = Enum.find(requests, &(&1.id == wait_id)) ->
          case choose(request, candidates, now) do
            nil -> {:ok, workflow}
            choice -> complete(workflow, request, choice)
          end

        true ->
          error(:stale_target)
      end
    end
  end

  def resolve(_workflow, _wait_id, _candidates, _now), do: error(:invalid_clock)

  defp choose(request, candidates, now) do
    request.options
    |> Enum.with_index()
    |> Enum.flat_map(fn {option, index} ->
      if is_integer(option.deadline) do
        if option.deadline <= now,
          do: [%{option: option, at: option.deadline, order: {0, index}, input: nil}],
          else: []
      else
        for candidate <- candidates,
            candidate.accepted_at <= now,
            matches_option?(option, candidate.input.event, candidate.input.payload),
            do: %{
              option: option,
              at: candidate.accepted_at,
              order: {1, candidate.order, index},
              input: candidate.input
            }
      end
    end)
    |> Enum.min_by(&{&1.at, &1.order}, fn -> nil end)
  end

  defp complete(workflow, request, choice) do
    node = Map.fetch!(workflow.graph.vertices, request.node_hash)
    fact = Map.fetch!(workflow.graph.vertices, request.input_id)

    with {:ok, runnable} <- Invokable.prepare(node, workflow, fact),
         {:ok, frame} <- Frame.merge(Jido.Exec.Fact.value(fact)) do
      output =
        Jido.Exec.Fact.child(fact,
          value: Frame.put_result(frame, node.component, result(request, choice), []),
          ancestry: {node.hash, fact.hash}
        )

      resolution =
        Fact.new(
          value: %{
            type: :jido_wait_resolution,
            version: 1,
            wait_id: request.id,
            path: request.path,
            selected: choice.option.name,
            accepted_at: choice.at,
            input_id: if(choice.input, do: choice.input.id)
          },
          meta: %{jido_wait_record: true},
          ancestry: {node.hash, fact.hash}
        )

      events = [
        FactProduced.new(output,
          producer_label: :produced,
          weight: runnable.context.ancestry_depth + 1
        ),
        %ActivationConsumed{fact_hash: fact.hash, node_hash: node.hash, from_label: :runnable},
        FactProduced.new(resolution, producer_label: :state_produced)
      ]

      {:ok, Workflow.apply_runnable(workflow, Runnable.complete(runnable, output, events))}
    end
  end

  defp result(request, choice) do
    value = if choice.input, do: choice.input.payload, else: %{fired_at: choice.at}

    if length(request.options) == 1,
      do: value,
      else: %{
        selected: choice.option.name,
        value: value,
        accepted_at: choice.at,
        input_id: if(choice.input, do: choice.input.id)
      }
  end

  defp matches_option?(option, event, payload),
    do:
      is_nil(option.deadline) and option.event == event and
        Enum.all?(option.match, fn {key, value} -> Map.fetch(payload, key) == {:ok, value} end)

  defp records(workflow, type) do
    for %Fact{meta: %{jido_wait_record: true}, value: %{type: ^type} = value} <-
          Workflow.facts(workflow),
        do: value
  end

  defp validate_candidates(candidates) when is_list(candidates) do
    if not List.improper?(candidates) and Enum.all?(candidates, &valid_candidate?/1),
      do: :ok,
      else: error(:invalid_candidate)
  end

  defp validate_candidates(_), do: error(:invalid_candidate)

  defp valid_candidate?(%{
         input: %{id: _, event: event, payload: payload},
         accepted_at: at,
         order: order
       }),
       do:
         is_binary(event) and is_map(payload) and not is_struct(payload) and
           is_integer(at) and at >= 0 and is_integer(order) and order >= 0

  defp valid_candidate?(_), do: false

  defp error(reason),
    do: {:error, Jido.Action.Error.config_error("wait operation rejected", %{reason: reason})}
end
