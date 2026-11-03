defmodule Jido.AgentServer.DurableTurn.WaitHost do
  @moduledoc false

  alias Jido.Exec.{Runtime, Wait}
  alias Runic.Workflow
  alias Runic.Workflow.{CausalContext, Fact, Runnable}
  alias Runic.Workflow.Events.FactProduced

  @input_limit 1_024

  def context(context, execution_id, workflow) do
    floor = acceptance_time(workflow, System.system_time(:millisecond))

    context
    |> Runtime.context(true)
    |> Runtime.wait_context(execution_id, fn -> max(System.system_time(:millisecond), floor) end)
  end

  def accept(workflow, input, now) do
    with :ok <- Wait.validate_input(input, now) do
      receipts = inputs(workflow)

      case Enum.find(receipts, &(&1.input.id == input.id)) do
        %{input: ^input} -> {:ok, workflow}
        %{} -> error(:conflicting_input_id)
        nil -> accept_new(workflow, input, now, receipts)
      end
    end
  end

  def resolve(workflow, now) when is_integer(now) and now >= 0 do
    receipts = inputs(workflow)
    now = acceptance_time(workflow, now)

    Enum.reduce_while(Runtime.pending_waits(workflow), {:ok, workflow}, fn request, {:ok, current} ->
      candidates = Enum.filter(receipts, &(&1.input.wait_id == request.id))

      case Runtime.resolve_wait(current, request.id, candidates, now) do
        {:error, _reason} = error -> {:halt, error}
        result -> {:cont, result}
      end
    end)
  end

  def resolve(_workflow, _now), do: error(:invalid_clock)

  defp accept_new(workflow, input, now, receipts) do
    request = Enum.find(Runtime.pending_waits(workflow), &(&1.id == input.wait_id))

    cond do
      is_nil(request) ->
        error(:stale_target)

      not Wait.matches?(request, input.event, input.payload) ->
        error(:unmatched_input)

      length(receipts) >= @input_limit ->
        error(:input_limit)

      true ->
        {:ok,
         record(workflow, %{
           type: :jido_wait_input,
           input: input,
           accepted_at: acceptance_time(workflow, now),
           order: length(receipts)
         })}
    end
  end

  # Wall-clock correction must not reorder saved acceptance. Receipt order
  # breaks ties when UTC time moves backwards or remains unchanged.
  defp acceptance_time(nil, now), do: now

  defp acceptance_time(workflow, now) do
    accepted = Enum.reduce(inputs(workflow), now, &max(&1.accepted_at, &2))
    Enum.reduce(Runtime.pending_waits(workflow), accepted, &max(&1.opened_at, &2))
  end

  defp inputs(workflow) do
    for %Fact{meta: %{jido_wait_record: true}, value: %{type: :jido_wait_input} = value} <-
          Workflow.facts(workflow),
        do: value
  end

  # Host receipts share the native log so the existing conditional checkpoint
  # write saves both host acceptance and Flow progress atomically.
  defp record(workflow, value) do
    root =
      Enum.find_value(workflow.graph.vertices, fn
        {id, %Workflow.Root{}} -> id
        _ -> nil
      end)

    fact =
      Fact.new(
        value: Map.put(value, :version, 1),
        meta: %{jido_wait_record: true},
        ancestry: {root, nil}
      )

    runnable =
      root
      |> Runnable.new(Workflow.root(), fact, %CausalContext{})
      |> Runnable.complete(nil, [FactProduced.new(fact, producer_label: :state_produced)])

    Workflow.apply_runnable(workflow, runnable)
  end

  defp error(reason),
    do: {:error, Jido.Error.config_error("wait host rejected operation", %{reason: reason})}
end
