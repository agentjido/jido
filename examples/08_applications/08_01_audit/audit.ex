defmodule Jido.Examples.Applications.Audit.Agent do
  @moduledoc "Commits domain and built-in Audit Plugin state in one Turn."
  use Jido.Agent, name: "application_audit_agent"

  agent do
    schema Zoi.object(%{successes: Zoi.integer() |> Zoi.default(0)})
    plugin Jido.Plugin.Audit, config: [max_entries: 2]
  end

  routes do
    route "examples.applications.audit.turn", Jido.Examples.Applications.Audit.Flow
  end
end

defmodule Jido.Examples.Applications.Audit.Decision do
  @moduledoc false
  use Jido.Action,
    name: "application_audit_decision",
    schema: Zoi.object(%{event: Zoi.map(), fail?: Zoi.boolean()})

  def run(%{event: event, fail?: fail?}, _context) do
    if fail?, do: {:error, :simulated_failure}, else: {:ok, %{event: event}}
  end
end

defmodule Jido.Examples.Applications.Audit.Expand do
  @moduledoc false
  use Jido.Action,
    name: "application_audit_expand",
    schema: Zoi.object(%{event: Zoi.map()})

  def run(params, _context), do: {:continue, params, Jido.Examples.Applications.Audit.Commit}
end

defmodule Jido.Examples.Applications.Audit.Flow do
  @moduledoc "Validates one event, then returns Agent and Plugin changes as one Flow result."

  use Jido.Flow,
    name: "application_audit_flow",
    schema: Zoi.object(%{event: Zoi.map(), fail?: Zoi.boolean()})

  flow do
    dispatch "decision",
      decision: Jido.Examples.Applications.Audit.Decision,
      expander: Jido.Examples.Applications.Audit.Expand,
      params: %{event: input(:event), fail?: input(:fail?)}

    output result("decision")
  end
end

defmodule Jido.Examples.Applications.Audit.Commit do
  @moduledoc "Applies the Agent state and audit Directive after the Flow decision succeeds."
  use Jido.Action,
    name: "application_audit_commit",
    schema: Zoi.object(%{event: Zoi.map()})

  @impl Jido.Action
  def run(%{event: event}, context) do
    next_state = %{context.agent_state | successes: context.agent_state.successes + 1}

    record =
      Jido.Plugin.Audit.record(event, :accepted, metadata: %{agent_id: context.agent_id})

    {:ok, next_state, [record]}
  end
end
