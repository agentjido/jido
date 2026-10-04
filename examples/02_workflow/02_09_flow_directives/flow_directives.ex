defmodule Jido.Examples.FlowDirectives do
  @moduledoc "Collects ordered Directives from a complete multi-step Flow."

  alias Jido.Examples.FlowDirectives.Effects

  use Jido.Agent, name: "workflow_flow_directives_agent"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    plugin Effects
  end

  routes do
    signal_source "/examples/workflow/flow_directives"
    route "examples.workflow.flow_directives.run", __MODULE__.Success, as: :run
    route "examples.workflow.flow_directives.fail", __MODULE__.Failure, as: :fail
  end

  defmodule RecordStep do
    @moduledoc false
    use Jido.Action,
      name: "workflow_flow_directives_record_step",
      schema: Zoi.object(%{label: Zoi.string() |> Zoi.min(1), count: Zoi.integer()})

    def run(input, context) do
      {:ok, %{context.agent_state | count: input.count}, [%Effects.Record{label: input.label}]}
    end
  end

  defmodule Reject do
    @moduledoc false
    use Jido.Action, name: "workflow_flow_directives_reject", schema: Zoi.object(%{})

    def run(_input, _context), do: {:error, :flow_rejected}
  end

  defmodule Success do
    @moduledoc "Three ordered components whose last result is the Agent candidate."
    use Jido.Flow,
      name: "workflow_flow_directives_success",
      schema: Zoi.object(%{}),
      output_schema: Zoi.object(%{count: Zoi.integer()})

    flow do
      step "first", action: RecordStep, params: %{label: "first", count: 1}
      step "side", action: RecordStep, params: %{label: "side", count: 2}, needs: ["first"]
      step "final", action: RecordStep, params: %{label: "final", count: 3}, needs: ["side"]
      output result("final")
    end
  end

  defmodule Failure do
    @moduledoc "A later failure discards Directives from earlier successful components."
    use Jido.Flow,
      name: "workflow_flow_directives_failure",
      schema: Zoi.object(%{}),
      output_schema: Zoi.object(%{count: Zoi.integer()})

    flow do
      step "first", action: RecordStep, params: %{label: "first", count: 1}
      step "side", action: RecordStep, params: %{label: "side", count: 2}, needs: ["first"]
      step "reject", action: Reject, params: %{}, needs: ["side"]
      output result("reject")
    end
  end
end
