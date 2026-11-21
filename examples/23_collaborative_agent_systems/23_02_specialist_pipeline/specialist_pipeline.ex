defmodule Jido.Examples.Collaboration.SpecialistPipeline.Classifier do
  use Jido.Agent, name: "example_pipeline_classifier"

  state do
    schema Jido.Joi.object(%{handled: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/collaboration/classifier"

    route "examples.collaboration.pipeline.classify", as: :classify do
      action %{mission_id: mission_id, report: report},
        schema:
          Jido.Joi.object(%{
            mission_id: Jido.Joi.string(),
            report: Jido.Joi.string()
          }),
        output_schema:
          Jido.Joi.object(%{
            state: Jido.Joi.map(),
            reply: Jido.Joi.map()
          }),
        context: context do
        category = if String.contains?(String.downcase(report), "database"), do: "database", else: "general"

        {:ok,
         %{
           state: %{handled: context.agent_state.handled + 1},
           reply: %{mission_id: mission_id, category: category, report: report}
         }}
      end

      state(from: output(:state))
      reply("examples.collaboration.pipeline.classified", from: output(:reply))
    end
  end
end

defmodule Jido.Examples.Collaboration.SpecialistPipeline.Diagnostician do
  use Jido.Agent, name: "example_pipeline_diagnostician"

  routes do
    signal_source "/examples/collaboration/diagnostician"

    route "examples.collaboration.pipeline.diagnose", as: :diagnose do
      action input,
        schema:
          Jido.Joi.object(%{
            mission_id: Jido.Joi.string(),
            category: Jido.Joi.string(),
            fail: Jido.Joi.boolean()
          }),
        output_schema: Jido.Joi.object(%{state: Jido.Joi.map(), reply: Jido.Joi.map()}),
        context: context do
        if input.fail do
          {:error, Jido.Error.execution_error("injected diagnostician failure")}
        else
          {:ok,
           %{
             state: context.agent_state,
             reply: %{
               mission_id: input.mission_id,
               category: input.category,
               cause: "connection pool saturation"
             }
           }}
        end
      end

      state(from: output(:state))
      reply("examples.collaboration.pipeline.diagnosed", from: output(:reply))
    end
  end
end

defmodule Jido.Examples.Collaboration.SpecialistPipeline.Responder do
  use Jido.Agent, name: "example_pipeline_responder"

  routes do
    signal_source "/examples/collaboration/responder"

    route "examples.collaboration.pipeline.respond", as: :respond do
      action input,
        schema:
          Jido.Joi.object(%{
            mission_id: Jido.Joi.string(),
            cause: Jido.Joi.string()
          }),
        output_schema: Jido.Joi.object(%{state: Jido.Joi.map(), reply: Jido.Joi.map()}),
        context: context do
        {:ok,
         %{
           state: context.agent_state,
           reply: %{
             mission_id: input.mission_id,
             cause: input.cause,
             action: "increase pool capacity"
           }
         }}
      end

      state(from: output(:state))
      reply("examples.collaboration.pipeline.responded", from: output(:reply))
    end
  end
end

defmodule Jido.Examples.Collaboration.SpecialistPipeline do
  alias Jido.Examples.Collaboration.SpecialistPipeline.{Classifier, Diagnostician, Responder}

  def run(mission_id, report, opts \\ []) do
    agents = %{
      classifier: Classifier.instantiate!(id: "#{mission_id}:classifier"),
      diagnostician: Diagnostician.instantiate!(id: "#{mission_id}:diagnostician"),
      responder: Responder.instantiate!(id: "#{mission_id}:responder")
    }

    with {:ok, classifier, classified} <-
           command(agents.classifier, Classifier.classify_signal!(%{mission_id: mission_id, report: report})),
         {:ok, diagnostician, diagnosed} <-
           command(
             agents.diagnostician,
             Diagnostician.diagnose_signal!(%{
               mission_id: mission_id,
               category: classified.category,
               fail: Keyword.get(opts, :fail_diagnosis, false)
             })
           ),
         {:ok, responder, responded} <-
           command(
             agents.responder,
             Responder.respond_signal!(%{mission_id: mission_id, cause: diagnosed.cause})
           ) do
      {:ok,
       %{
         mission_id: mission_id,
         artifacts: %{classification: classified, diagnosis: diagnosed, response: responded},
         agents: %{classifier: classifier, diagnostician: diagnostician, responder: responder}
       }}
    end
  end

  defp command(agent, signal) do
    case Jido.Agent.cmd(agent, signal) do
      {:ok, candidate, [%Jido.Agent.Directive.Reply{signal: reply}]} ->
        {:ok, candidate, reply.data}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
