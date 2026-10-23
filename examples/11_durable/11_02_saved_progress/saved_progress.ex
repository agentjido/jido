defmodule Jido.Examples.Durable.SavedProgress do
  @moduledoc "A sequential ten-step Flow with one Action per recovery boundary."
  use Jido.Flow,
    name: "durable_saved_progress",
    schema: Zoi.object(%{value: Zoi.integer()}),
    output_schema: Zoi.object(%{value: Zoi.integer()})

  alias Jido.Examples.Durable.SavedProgress.Advance

  flow do
    step "step_1", action: Advance, params: %{step: 1, value: input(:value)}
    step "step_2", action: Advance, params: %{step: 2, value: result("step_1", :value)}
    step "step_3", action: Advance, params: %{step: 3, value: result("step_2", :value)}
    step "step_4", action: Advance, params: %{step: 4, value: result("step_3", :value)}
    step "step_5", action: Advance, params: %{step: 5, value: result("step_4", :value)}
    step "step_6", action: Advance, params: %{step: 6, value: result("step_5", :value)}
    step "step_7", action: Advance, params: %{step: 7, value: result("step_6", :value)}
    step "step_8", action: Advance, params: %{step: 8, value: result("step_7", :value)}
    step "step_9", action: Advance, params: %{step: 9, value: result("step_8", :value)}
    step "step_10", action: Advance, params: %{step: 10, value: result("step_9", :value)}

    output result("step_10")
  end
end

defmodule Jido.Examples.Durable.SavedProgress.Agent do
  @moduledoc "Runs the ten-step Flow as one serial AgentServer Turn."
  use Jido.Agent, name: "durable_saved_progress_agent"

  state do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/durable/saved_progress"

    route "examples.durable.saved_progress.run", Jido.Examples.Durable.SavedProgress, as: :run do
      state(from: output())
    end
  end
end
