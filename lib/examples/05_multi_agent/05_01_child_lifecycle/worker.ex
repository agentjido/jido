defmodule Jido.Examples.Worker.Calculate do
  @moduledoc false
  use Jido.Action,
    name: "example_worker_calculate",
    schema:
      Zoi.object(%{
        request_id: Zoi.string() |> Zoi.min(1),
        job_id: Zoi.string() |> Zoi.min(1),
        tag: Zoi.string() |> Zoi.min(1),
        value: Zoi.integer()
      })

  def run(input, context) do
    # An optional observer can hold execution in tests. It supplies no result.
    if observer = context[:on_work], do: observer.(input)
    result = Map.put(input, :value, input.value * 2)
    reply = Jido.Signal.new!("examples.work.result", result, source: "/examples/worker")

    {:ok, %{completed: context.agent_state.completed ++ [result]},
     [Jido.Agent.Directive.emit_to_parent(reply)]}
  end
end

defmodule Jido.Examples.Worker do
  @moduledoc "A child Agent that doubles an integer and sends its parent a result Signal."
  use Jido.Agent, name: "example_worker"

  agent do
    schema Zoi.object(%{completed: Zoi.list(Zoi.map()) |> Zoi.default([])})
  end

  routes do
    signal_source "/examples/worker"

    route "examples.work.calculate", Jido.Examples.Worker.Calculate do
      define :calculate, args: [:request_id, :job_id, :tag, :value]
    end
  end
end

defmodule Jido.Examples.KeepState do
  @moduledoc false
  use Jido.Action, name: "example_keep_state"
  def run(_, %{agent_state: state}), do: {:ok, state}
end
