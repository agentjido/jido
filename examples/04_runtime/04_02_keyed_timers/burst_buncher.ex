defmodule Jido.Examples.BurstBuncher do
  @moduledoc """
  An Agent collects short bursts into stable ordered batches.

  The Agent owns buffer and duplicate policy. Its Timer Plugin owns keyed OTP
  timers. Each accepted item replaces the pending flush timer. A size or time
  flush commits the empty buffer before it emits the batch Signal.
  """

  use Jido.Agent,
    name: "examples_burst_buncher",
    description: "Collects ordered items and flushes stable batches"

  agent do
    schema Zoi.object(%{
             buffer: Zoi.list(Zoi.map()) |> Zoi.default([]),
             handled_item_ids: Zoi.list(Zoi.string()) |> Zoi.default([]),
             max_size: Zoi.integer() |> Zoi.min(1) |> Zoi.default(3),
             flush_delay_ms: Zoi.integer() |> Zoi.min(0) |> Zoi.default(50),
             timer_generation: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0),
             next_batch_number: Zoi.integer() |> Zoi.min(1) |> Zoi.default(1),
             last_flush_reason: Zoi.enum([:size, :timeout]) |> Zoi.nullable() |> Zoi.default(nil)
           })

    plugin Jido.Examples.BurstBuncher.Timer
  end

  routes do
    signal_source "/examples/runtime/burst_buncher"

    route "examples.runtime.burst_buncher.add" do
      action input,
        schema:
          Zoi.object(%{
            item_id: Zoi.string() |> Zoi.min(1),
            item: Zoi.any()
          }),
        context: context do
        state = context.agent_state

        if input.item_id in state.handled_item_ids do
          {:ok, state}
        else
          buffer = state.buffer ++ [%{id: input.item_id, value: input.item}]
          generation = state.timer_generation + 1

          candidate = %{
            state
            | buffer: buffer,
              handled_item_ids: state.handled_item_ids ++ [input.item_id],
              timer_generation: generation
          }

          if length(buffer) >= state.max_size do
            batch =
              Jido.Examples.BurstBuncher.batch_signal!(
                candidate.next_batch_number,
                candidate.buffer,
                :size
              )

            completed = %{
              candidate
              | buffer: [],
                next_batch_number: candidate.next_batch_number + 1,
                last_flush_reason: :size
            }

            {:ok, completed,
             [
               Jido.Examples.BurstBuncher.Timer.cancel(:flush),
               Jido.Agent.Directive.emit(batch)
             ]}
          else
            timer =
              Jido.Examples.BurstBuncher.Timer.replace(
                :flush,
                state.flush_delay_ms,
                Jido.Examples.BurstBuncher.timer_flush_signal!(generation)
              )

            {:ok, candidate, [timer]}
          end
        end
      end

      define :add_item, args: [:item_id, :item]
    end

    route "examples.runtime.burst_buncher.flush" do
      action %{generation: generation},
        schema: Zoi.object(%{generation: Zoi.integer() |> Zoi.min(0)}),
        context: context do
        state = context.agent_state

        if generation == state.timer_generation and state.buffer != [] do
          batch =
            Jido.Examples.BurstBuncher.batch_signal!(
              state.next_batch_number,
              state.buffer,
              :timeout
            )

          candidate = %{
            state
            | buffer: [],
              next_batch_number: state.next_batch_number + 1,
              last_flush_reason: :timeout
          }

          {:ok, candidate,
           [
             Jido.Examples.BurstBuncher.Timer.cancel(:flush),
             Jido.Agent.Directive.emit(batch)
           ]}
        else
          {:ok, state}
        end
      end

      define :flush, args: [:generation]
    end
  end

  alias Jido.Signal

  @doc "Builds one timer flush Signal for a known generation."
  @spec timer_flush_signal!(non_neg_integer()) :: Signal.t()
  def timer_flush_signal!(generation) when is_integer(generation) and generation >= 0 do
    flush_signal!(generation, signal: [source: "/examples/runtime/burst_buncher/timer"])
  end

  @doc false
  @spec batch_signal!(pos_integer(), [map()], :size | :timeout) :: Signal.t()
  def batch_signal!(number, items, reason) do
    Signal.new!(
      "examples.runtime.burst_buncher.batch",
      %{batch_id: "batch-#{number}", items: items, reason: reason},
      source: "/examples/runtime/burst_buncher"
    )
  end
end
