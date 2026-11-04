defmodule Jido.Examples.Applications.PurposeLoop.Signals do
  @moduledoc "Builds the scheduled tick Signal used by the purpose loop."

  alias Jido.Signal

  def tick(generation, sequence) do
    Signal.new!(
      "examples.applications.purpose_loop.tick",
      %{generation: generation, sequence: sequence},
      source: "/examples/applications/purpose_loop/clock"
    )
  end
end

defmodule Jido.Examples.Applications.PurposeLoop.Clock do
  @moduledoc "Creates Scheduler Directives for the purpose loop."

  alias Jido.Examples.Applications.PurposeLoop.Signals
  alias Jido.Plugin.Scheduler

  def schedule_tick(state, delay_ms) do
    Scheduler.schedule(delay_ms, Signals.tick(state.generation, state.next_sequence))
  end
end
