defmodule Jido.Examples.Applications.Audit.Agent do
  @moduledoc "Commits domain and built-in Audit Plugin state in one Turn."
  use Jido.Agent,
    name: "application_audit_agent",
    plugins: [{Jido.Plugin.Audit, %{max_entries: 2}}]

  state do
    schema Jido.Joi.object(%{successes: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    route "examples.applications.audit.turn", Jido.Examples.Applications.Audit.Flow
  end
end

defmodule Jido.Examples.Applications.Audit.Flow do
  @moduledoc "Validates an event before one domain and Audit state commit."
  use Jido.Flow,
    name: "application_audit_flow",
    schema: Jido.Joi.object(%{event: Jido.Joi.map(), fail?: Jido.Joi.boolean()}),
    output_schema:
      Jido.Joi.object(%{
        successes: Jido.Joi.integer(),
        audit: Jido.Joi.object(%{records: Jido.Joi.list(Jido.Joi.struct(Jido.Plugin.Audit.Record))})
      })

  flow do
    step "guard", input <- input() do
      if input.fail?, do: {:error, :simulated_failure}, else: {:ok, input.event}
    end

    step "commit", event <- result("guard"), inline: [context: context] do
      state = %{context.agent_state | successes: context.agent_state.successes + 1}
      record = Jido.Plugin.Audit.record(event, :accepted, metadata: %{agent_id: context.agent_id})
      {:ok, state, [record]}
    end

    output result("commit")
  end
end
