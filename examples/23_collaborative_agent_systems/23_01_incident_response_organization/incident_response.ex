defmodule Jido.Examples.Collaboration.IncidentResponse.Analyst do
  use Jido.Agent, name: "example_incident_analyst"
end

defmodule Jido.Examples.Collaboration.IncidentResponse.TriageTeam do
  alias Jido.Joi

  use Jido.Agent, name: "example_incident_triage_team"

  state do
    schema Joi.object(%{triaged: Joi.integer() |> Joi.default(0)})
  end

  routes do
    route "examples.incident.triage.request" do
      action input,
        schema:
          Joi.object(%{
            incident_id: Joi.string(),
            severity: Joi.string(),
            fail_audit: Joi.boolean()
          }),
        context: context do
        completed =
          Jido.Signal.new!(
            "examples.incident.triage.completed",
            %{
              incident_id: input.incident_id,
              severity: input.severity,
              fail_audit: input.fail_audit,
              finding: "database saturation"
            },
            source: "/examples/incident/triage"
          )

        {:ok, %{triaged: context.agent_state.triaged + 1}, [Jido.Agent.Directive.emit(completed)]}
      end
    end
  end

  topology do
    agent :analysts, Jido.Examples.Collaboration.IncidentResponse.Analyst do
      count 2
    end
  end
end

defmodule Jido.Examples.Collaboration.IncidentResponse.RemediationTeam do
  alias Jido.Joi

  use Jido.Agent, name: "example_incident_remediation_team"

  state do
    schema Joi.object(%{contained: Joi.integer() |> Joi.default(0)})
  end

  routes do
    route "examples.incident.triage.completed" do
      action input,
        schema:
          Joi.object(%{
            incident_id: Joi.string(),
            severity: Joi.string(),
            fail_audit: Joi.boolean(),
            finding: Joi.string()
          }),
        context: context do
        contained =
          Jido.Signal.new!(
            "examples.incident.remediation.contained",
            %{
              incident_id: input.incident_id,
              action: "shed noncritical load",
              finding: input.finding
            },
            source: "/examples/incident/remediation"
          )

        {:ok, %{contained: context.agent_state.contained + 1}, [Jido.Agent.Directive.emit(contained)]}
      end
    end
  end
end

defmodule Jido.Examples.Collaboration.IncidentResponse.AuditTeam do
  alias Jido.Joi

  use Jido.Agent, name: "example_incident_audit_team"

  state do
    schema Joi.object(%{records: Joi.list(Joi.map()) |> Joi.default([])})
  end

  routes do
    route "examples.incident.triage.completed" do
      action input,
        schema:
          Joi.object(%{
            incident_id: Joi.string(),
            severity: Joi.string(),
            fail_audit: Joi.boolean(),
            finding: Joi.string()
          }),
        context: context do
        if input.fail_audit do
          {:error, Jido.Error.execution_error("injected audit team failure")}
        else
          record = Map.take(input, [:incident_id, :severity, :finding])
          {:ok, %{records: context.agent_state.records ++ [record]}}
        end
      end
    end
  end
end

defmodule Jido.Examples.Collaboration.IncidentResponse.Coordinator do
  alias Jido.Joi

  use Jido.Agent, name: "example_incident_response_coordinator"

  state do
    schema Joi.object(%{
             incident_id: Joi.string() |> Joi.default(""),
             status:
               Joi.enum([:idle, :triaging, :awaiting_approval, :resolved])
               |> Joi.default(:idle),
             severity: Joi.string() |> Joi.default(""),
             remediation: Joi.string() |> Joi.default(""),
             events: Joi.list(Joi.map()) |> Joi.default([])
           })
  end

  routes do
    signal_source "/examples/incident/coordinator"

    route "examples.incident.reported", as: :report do
      action input,
        schema:
          Joi.object(%{
            incident_id: Joi.string() |> Joi.min(1),
            severity: Joi.string() |> Joi.min(1),
            fail_audit: Joi.boolean()
          }),
        context: context do
        state = context.agent_state

        if state.incident_id == input.incident_id do
          {:error, Jido.Error.validation_error("incident report was already accepted")}
        else
          triage =
            Jido.Signal.new!("examples.incident.triage.request", input, source: "/examples/incident/coordinator")

          state = %{
            state
            | incident_id: input.incident_id,
              status: :triaging,
              severity: input.severity,
              events: [%{event: :reported, incident_id: input.incident_id}]
          }

          {:ok, state, [Jido.Agent.Directive.emit(triage)]}
        end
      end
    end

    route "examples.incident.remediation.contained" do
      action input,
        schema:
          Joi.object(%{
            incident_id: Joi.string(),
            action: Joi.string(),
            finding: Joi.string()
          }),
        context: context do
        state = context.agent_state

        if state.status == :triaging and state.incident_id == input.incident_id do
          {:ok,
           %{
             state
             | status: :awaiting_approval,
               remediation: input.action,
               events: state.events ++ [%{event: :contained, finding: input.finding}]
           }}
        else
          {:error, Jido.Error.validation_error("contained result is stale")}
        end
      end
    end

    route "examples.incident.approved", as: :approve do
      action %{incident_id: incident_id},
        schema: Joi.object(%{incident_id: Joi.string()}),
        context: context do
        state = context.agent_state

        if state.status == :awaiting_approval and state.incident_id == incident_id do
          {:ok,
           %{
             state
             | status: :resolved,
               events: state.events ++ [%{event: :approved, incident_id: incident_id}]
           }}
        else
          {:error, Jido.Error.validation_error("approval is stale or premature")}
        end
      end
    end
  end

  topology do
    agent :triage, Jido.Examples.Collaboration.IncidentResponse.TriageTeam
    agent :remediation, Jido.Examples.Collaboration.IncidentResponse.RemediationTeam
    agent :audit, Jido.Examples.Collaboration.IncidentResponse.AuditTeam

    connections do
      connect "examples.incident.triage.request", from: :root, to: :triage
      connect "examples.incident.triage.completed", from: :triage, to: :remediation
      connect "examples.incident.triage.completed", from: :triage, to: :audit
      connect "examples.incident.remediation.contained", from: :remediation, to: :root
    end
  end
end
