defmodule Jido.Examples.Collaboration.ResearchTeam.Researcher do
  use Jido.Agent, name: "example_research_team_researcher"

  state do
    schema Jido.Joi.object(%{completed: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/collaboration/researcher"

    route "examples.collaboration.research.gather", as: :gather do
      action input,
        schema:
          Jido.Joi.object(%{
            mission_id: Jido.Joi.string(),
            topic: Jido.Joi.string(),
            source_id: Jido.Joi.string(),
            fail: Jido.Joi.boolean()
          }),
        output_schema: Jido.Joi.object(%{state: Jido.Joi.map(), reply: Jido.Joi.map()}),
        context: context do
        if input.fail do
          {:error, Jido.Error.execution_error("injected research failure")}
        else
          {:ok,
           %{
             state: %{completed: context.agent_state.completed + 1},
             reply: %{
               mission_id: input.mission_id,
               source_id: input.source_id,
               evidence: "#{input.topic} evidence from #{input.source_id}"
             }
           }}
        end
      end

      state(from: output(:state))
      reply("examples.collaboration.research.evidence", from: output(:reply))
    end
  end
end

defmodule Jido.Examples.Collaboration.ResearchTeam.Analyst do
  use Jido.Agent, name: "example_research_team_analyst"

  routes do
    signal_source "/examples/collaboration/analyst"

    route "examples.collaboration.research.analyze", as: :analyze do
      action input,
        schema:
          Jido.Joi.object(%{
            mission_id: Jido.Joi.string(),
            evidence: Jido.Joi.list(Jido.Joi.map()) |> Jido.Joi.min(1)
          }),
        output_schema: Jido.Joi.object(%{state: Jido.Joi.map(), reply: Jido.Joi.map()}),
        context: context do
        {:ok,
         %{
           state: context.agent_state,
           reply: %{
             mission_id: input.mission_id,
             finding: "#{length(input.evidence)} supported findings",
             source_ids: Enum.map(input.evidence, & &1.source_id)
           }
         }}
      end

      state(from: output(:state))
      reply("examples.collaboration.research.finding", from: output(:reply))
    end
  end
end

defmodule Jido.Examples.Collaboration.ResearchTeam.Writer do
  use Jido.Agent, name: "example_research_team_writer"

  routes do
    signal_source "/examples/collaboration/writer"

    route "examples.collaboration.research.write", as: :write do
      action input,
        schema:
          Jido.Joi.object(%{
            mission_id: Jido.Joi.string(),
            finding: Jido.Joi.string(),
            revision: Jido.Joi.integer(),
            feedback: Jido.Joi.string()
          }),
        output_schema: Jido.Joi.object(%{state: Jido.Joi.map(), reply: Jido.Joi.map()}),
        context: context do
        suffix = if input.feedback == "", do: "", else: " Revised for: #{input.feedback}."

        {:ok,
         %{
           state: context.agent_state,
           reply: %{
             mission_id: input.mission_id,
             revision: input.revision,
             draft: "Draft #{input.revision}: #{input.finding}.#{suffix}"
           }
         }}
      end

      state(from: output(:state))
      reply("examples.collaboration.research.draft", from: output(:reply))
    end
  end
end

defmodule Jido.Examples.Collaboration.ResearchTeam.Critic do
  use Jido.Agent, name: "example_research_team_critic"

  routes do
    signal_source "/examples/collaboration/critic"

    route "examples.collaboration.research.review", as: :review do
      action input,
        schema:
          Jido.Joi.object(%{
            mission_id: Jido.Joi.string(),
            draft: Jido.Joi.string(),
            revision: Jido.Joi.integer()
          }),
        output_schema: Jido.Joi.object(%{state: Jido.Joi.map(), reply: Jido.Joi.map()}),
        context: context do
        decision = if input.revision == 0, do: :revise, else: :approve
        feedback = if decision == :revise, do: "name the evidence count", else: ""

        {:ok,
         %{
           state: context.agent_state,
           reply: %{
             mission_id: input.mission_id,
             revision: input.revision,
             decision: decision,
             feedback: feedback,
             reviewed_draft: input.draft
           }
         }}
      end

      state(from: output(:state))
      reply("examples.collaboration.research.reviewed", from: output(:reply))
    end
  end
end

defmodule Jido.Examples.Collaboration.ResearchTeam do
  alias Jido.Examples.Collaboration.ResearchTeam.{Analyst, Critic, Researcher, Writer}

  @max_revisions 1

  def run(mission_id, topic, sources) do
    evidence =
      sources
      |> Task.async_stream(
        fn source -> research(mission_id, topic, source) end,
        ordered: true,
        max_concurrency: 2,
        timeout: 1_000
      )
      |> Enum.flat_map(fn
        {:ok, {:ok, item}} -> [item]
        {:ok, {:error, _reason}} -> []
      end)

    with true <- evidence != [],
         {:ok, finding} <-
           command(
             Analyst.instantiate!(id: "#{mission_id}:analyst"),
             Analyst.analyze_signal!(%{mission_id: mission_id, evidence: evidence})
           ),
         {:ok, publication} <- draft_and_review(mission_id, finding, 0, "") do
      {:ok,
       %{
         mission_id: mission_id,
         owner: :coordinator,
         evidence: evidence,
         finding: finding,
         publication: publication,
         budgets: %{researchers: 2, revisions: @max_revisions}
       }}
    else
      false -> {:error, :insufficient_evidence}
      {:error, _reason} = error -> error
    end
  end

  defp research(mission_id, topic, source) do
    command(
      Researcher.instantiate!(id: "#{mission_id}:researcher:#{source.source_id}"),
      Researcher.gather_signal!(%{
        mission_id: mission_id,
        topic: topic,
        source_id: source.source_id,
        fail: source.fail
      })
    )
  end

  defp draft_and_review(mission_id, finding, revision, feedback) do
    with {:ok, draft} <-
           command(
             Writer.instantiate!(id: "#{mission_id}:writer"),
             Writer.write_signal!(%{
               mission_id: mission_id,
               finding: finding.finding,
               revision: revision,
               feedback: feedback
             })
           ),
         {:ok, review} <-
           command(
             Critic.instantiate!(id: "#{mission_id}:critic"),
             Critic.review_signal!(%{
               mission_id: mission_id,
               draft: draft.draft,
               revision: revision
             })
           ) do
      case {review.decision, revision < @max_revisions} do
        {:revise, true} -> draft_and_review(mission_id, finding, revision + 1, review.feedback)
        {:approve, _} -> {:ok, %{draft: draft, review: review}}
        {:revise, false} -> {:error, :revision_budget_exhausted}
      end
    end
  end

  defp command(agent, signal) do
    case Jido.Agent.cmd(agent, signal) do
      {:ok, _candidate, [%Jido.Agent.Directive.Reply{signal: reply}]} -> {:ok, reply.data}
      {:error, reason} -> {:error, reason}
    end
  end
end
