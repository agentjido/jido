defmodule Jido.Examples.ExecutableContinuation.Expand do
  @moduledoc false
  use Jido.Action, name: "workflow_continuation_expand"

  def run(%{remaining: 0} = input, context) do
    {:ok,
     %{
       value: if(context[:invalid_final], do: -1, else: input.value),
       request: Map.get(context, :request, "none")
     }}
  end

  def run(input, _context), do: {:continue, input, Jido.Examples.ExecutableContinuation.Add}
end

defmodule Jido.Examples.ExecutableContinuation.Add do
  @moduledoc false
  use Jido.Action, name: "workflow_continuation_add"

  def run(input, context) do
    Jido.Examples.Workflow.Observation.record(context, {:add, input.value}, %{
      request: context[:request],
      agent: context.agent_id
    })

    {:continue, %{input | value: input.value + 1, remaining: input.remaining - 1},
     Jido.Examples.ExecutableContinuation.Pipeline}
  end
end

defmodule Jido.Examples.ExecutableContinuation.Pipeline do
  @moduledoc "Terminal Dispatch selects a result or the next executable in the same Exec call."
  use Jido.Flow,
    name: "workflow_continuation",
    schema:
      Zoi.object(%{value: Zoi.integer() |> Zoi.min(0), remaining: Zoi.integer() |> Zoi.min(0)}),
    output_schema: Zoi.object(%{value: Zoi.integer() |> Zoi.min(0), request: Zoi.string()})

  flow do
    dispatch "next" do
      decision input <- input(), context: context do
        Jido.Examples.Workflow.Observation.record(context, {:decision, input.value}, input)
        {:ok, input}
      end

      expander Jido.Examples.ExecutableContinuation.Expand
    end

    output result("next")
  end
end

defmodule Jido.Examples.ExecutableContinuation do
  @moduledoc "One Turn owns the complete Flow/Action continuation chain."
  use Jido.Agent, name: "workflow_continuation_agent"

  agent do
    schema Zoi.object(%{
             value: Zoi.integer() |> Zoi.default(0),
             request: Zoi.string() |> Zoi.default("")
           })
  end

  routes do
    signal_source "/workflow"

    route "workflow.continuation", Jido.Examples.ExecutableContinuation.Pipeline do
      define :add_repeatedly, args: [:value, :remaining]
    end
  end
end
