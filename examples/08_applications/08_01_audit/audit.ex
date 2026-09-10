defmodule Jido.Examples.Applications.Audit.Agent do
  @moduledoc "Commits Agent and audit Plugin state only when the complete Flow succeeds."
  use Jido.Agent, name: "application_audit_agent"

  agent do
    schema Zoi.object(%{successes: Zoi.integer() |> Zoi.default(0)})
    plugin Jido.Examples.Applications.Audit.Plugin
  end

  routes do
    route "examples.applications.audit.turn", Jido.Examples.Applications.Audit.Flow
  end
end

defmodule Jido.Examples.Applications.Audit.Flow do
  @moduledoc "Validates one event, then returns Agent and Plugin changes as one Flow result."

  use Jido.Flow,
    name: "application_audit_flow",
    schema: Zoi.object(%{event: Zoi.any(), fail?: Zoi.boolean()})

  flow do
    dispatch "decision" do
      decision [event <- input(:event), fail? <- input(:fail?)] do
        if fail?, do: {:error, :simulated_failure}, else: {:ok, %{event: event}}
      end

      expander params do
        {:continue, params, Jido.Examples.Applications.Audit.Commit}
      end
    end

    output result("decision")
  end
end

defmodule Jido.Examples.Applications.Audit.Commit do
  @moduledoc "Applies the Agent state and audit Directive after the Flow decision succeeds."
  use Jido.Action, name: "application_audit_commit"

  @impl Jido.Action
  def run(%{event: event}, context) do
    next_state = %{context.agent_state | successes: context.agent_state.successes + 1}
    {:ok, next_state, [Jido.Examples.Applications.Audit.Plugin.record(event, :accepted)]}
  end
end
