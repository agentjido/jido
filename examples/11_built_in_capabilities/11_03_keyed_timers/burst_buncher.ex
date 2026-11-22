defmodule Jido.Examples.BurstBuncher do
  @moduledoc """
  An Agent collects short bursts into stable ordered batches.

  The Agent owns buffer and duplicate policy. Its Timer Plugin owns keyed OTP
  timers. Each accepted item replaces the pending flush timer. A size or time
  flush commits the empty buffer before it emits the batch Signal.
  """

  alias Jido.Joi

  use Jido.Agent,
    name: "examples_burst_buncher",
    description: "Collects ordered items and flushes stable batches",
    plugins: [Jido.Examples.BurstBuncher.Timer]

  state do
    schema Joi.object(%{
             buffer: Joi.list(Joi.map()) |> Joi.default([]),
             handled_item_ids: Joi.list(Joi.string()) |> Joi.default([]),
             max_size: Joi.integer() |> Joi.min(1) |> Joi.default(3),
             flush_delay_ms: Joi.integer() |> Joi.min(0) |> Joi.default(50),
             timer_generation: Joi.integer() |> Joi.min(0) |> Joi.default(0),
             next_batch_number: Joi.integer() |> Joi.min(1) |> Joi.default(1),
             last_flush_reason: Joi.enum([:size, :timeout]) |> Joi.nullable() |> Joi.default(nil)
           })
  end

  routes do
    signal_source "/examples/runtime/burst_buncher"

    route "examples.runtime.burst_buncher.add", as: :add_item do
      action input,
        schema:
          Joi.object(%{
            item_id: Joi.string() |> Joi.min(1),
            item: Joi.any()
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
    end

    route "examples.runtime.burst_buncher.flush", as: :flush do
      action %{generation: generation},
        schema: Joi.object(%{generation: Joi.integer() |> Joi.min(0)}),
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
    end
  end

  alias Jido.Signal

  @doc "Builds one timer flush Signal for a known generation."
  @spec timer_flush_signal!(non_neg_integer()) :: Signal.t()
  def timer_flush_signal!(generation) when is_integer(generation) and generation >= 0 do
    {:ok, signal} =
      flush_signal(%{generation: generation}, source: "/examples/runtime/burst_buncher/timer")

    signal
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
