defmodule Jido.AgentServer.WaitHost do
  @moduledoc false

  alias Jido.Exec.Waits
  alias Runic.Workflow
  alias Runic.Workflow.{CausalContext, Fact, Runnable}
  alias Runic.Workflow.Events.FactProduced

  @input_limit 1_024

  def context(context, execution_id, workflow) do
    floor = acceptance_time(workflow, 0)

    context
    |> Jido.Exec.Runtime.context(true)
    |> Waits.context(execution_id, fn -> max(System.system_time(:millisecond), floor) end)
  end

  def accept(workflow, input, now) do
    with :ok <- valid_input(input, now),
         :ok <- Jido.PortableTerm.validate(input, :wait_event) do
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

    Enum.reduce_while(Waits.pending(workflow), {:ok, workflow}, fn request, {:ok, current} ->
      candidates = Enum.filter(receipts, &(&1.input.wait_id == request.id))

      case Waits.resolve(current, request.id, candidates, now) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  def resolve(_workflow, _now), do: error(:invalid_clock)

  defp accept_new(workflow, input, now, receipts) do
    request = Enum.find(Waits.pending(workflow), &(&1.id == input.wait_id))

    cond do
      is_nil(request) ->
        error(:stale_target)

      not Waits.matches?(request, input.event, input.payload) ->
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
    Enum.reduce(Waits.pending(workflow), accepted, &max(&1.opened_at, &2))
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

  defp valid_input(%{id: id, event: event, payload: payload, wait_id: wait_id} = input, now)
       when is_binary(id) and byte_size(id) > 0 and is_binary(event) and byte_size(event) > 0 and
              is_binary(wait_id) and byte_size(wait_id) > 0 and is_map(payload) and
              not is_struct(payload) and is_integer(now) and now >= 0 do
    if map_size(input) == 4, do: :ok, else: error(:invalid_input)
  end

  defp valid_input(_input, _now), do: error(:invalid_input)

  defp error(reason),
    do:
      {:error, Jido.Action.Error.config_error("wait host rejected operation", %{reason: reason})}
end
