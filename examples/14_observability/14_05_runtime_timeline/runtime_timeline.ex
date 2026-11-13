defmodule Jido.Examples.Observability.RuntimeTimeline.Agent do
  @moduledoc "Waits for one matching release Signal."

  use Jido.Agent, name: "examples_observability_runtime_timeline_agent"

  state do
    schema Jido.Joi.object(%{
             request_id: Jido.Joi.string() |> Jido.Joi.default(""),
             status: Jido.Joi.enum([:idle, :completed]) |> Jido.Joi.default(:idle)
           })
  end

  routes do
    signal_source "/examples/observability/runtime_timeline"

    route "examples.observability.runtime_timeline.request",
          Jido.Examples.Observability.RuntimeTimeline.ReleaseFlow,
          as: :request
  end

  @doc "Builds the Signal that releases one waiting request."
  def release_signal(request_id) do
    Jido.Signal.new(
      "examples.observability.runtime_timeline.release",
      %{request_id: request_id},
      source: "/examples/observability/runtime_timeline/reviewer"
    )
  end
end

defmodule Jido.Examples.Observability.RuntimeTimeline.ReleaseFlow do
  @moduledoc "Keeps the wait and completion in one Turn."

  use Jido.Flow,
    name: "examples_observability_runtime_timeline_release",
    schema: Jido.Joi.object(%{request_id: Jido.Joi.string() |> Jido.Joi.min(1)})

  flow do
    step "request", request <- input() do
      {:ok, request}
    end

    selection "decision" do
      needs ["request"]

      await "release",
        event: "examples.observability.runtime_timeline.release",
        match: %{request_id: result("request", :request_id)}
    end

    step "complete",
         values <- %{request: result("request"), decision: result("decision")},
         inline: [context: context] do
      {:ok,
       %{
         context.agent_state
         | request_id: values.request.request_id,
           status: :completed
       }}
    end

    output result("complete")
  end
end

defmodule Jido.Examples.Observability.RuntimeTimeline do
  @moduledoc "Builds a process-neutral application projection from runtime status."

  @doc "Selects stable operational fields for one timeline point."
  def project(label, %Jido.AgentServer.Status{} = status) do
    %{
      active_turn_id: status.active_turn_id,
      agent_revision: status.agent_revision,
      label: label,
      last_outcome: status.last_outcome,
      queue_depth: status.queue_depth,
      residency: status.residency,
      wait_count: length(status.waits),
      work_state: status.work_state
    }
  end
end
