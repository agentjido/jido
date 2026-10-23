defmodule JidoTest.ComposableAgent.Definitions.Team do
  use Jido.Agent,
    name: "research_team",
    description: "Coordinates research and records a report",
    metadata: %{purpose: "research"},
    extensions: [
      Jido.Plugin.Scheduler.DSL,
      Jido.Plugin.Bus.DSL
    ]

  alias __MODULE__.{RecordReport, Worker}

  state do
    schema Zoi.object(%{
             query: Zoi.string() |> Zoi.default(""),
             workers: Zoi.integer() |> Zoi.default(2),
             report: Zoi.string() |> Zoi.default("")
           })
  end

  routes do
    signal_source "/research/team"

    route "research.query.set", as: :set_query, defaults: %{query: ""} do
      action %{query: query},
        schema: Zoi.object(%{query: Zoi.string()}),
        context: context do
        {:ok, %{context.agent_state | query: query}}
      end
    end

    route "research.report.record", RecordReport, as: :record_report

    route "research.report.prepared", RecordReport

    route "external.research.request", as: :request_work do
      transform(signal) do
        case signal.data do
          %{"prompt" => prompt} when is_binary(prompt) ->
            {:ok, %{signal | type: "research.work.request", data: %{query: String.trim(prompt)}}}

          _ ->
            {:error, :invalid_prompt}
        end
      end
    end

    route "external.research.prompted", as: :request_work_from_prompt do
      transform do
        %Jido.Signal{data: %{"prompt" => prompt}} = signal when is_binary(prompt) ->
          {:ok, %{signal | type: "research.work.request", data: %{query: String.trim(prompt)}}}

        %Jido.Signal{data: %{"query" => query}} = signal when is_binary(query) ->
          {:ok, %{signal | type: "research.work.request", data: %{query: String.trim(query)}}}

        _signal ->
          {:error, :invalid_prompt}
      end
    end

    route "research.work.request" do
      forward(to: agent(:researchers))
    end

    route "research.plan.request" do
      forward(to: agent(:planner))
    end
  end

  schedules do
    schedule :review_research do
      every(60_000)
      signal(%{type: "research.plan.request", data: %{query: "Review active research"}})
    end

    schedule :refresh_research,
      cron: "*/5 * * * *",
      timezone: "Etc/UTC",
      signal: %{type: "research.work.request", data: %{query: "Refresh research findings"}}
  end

  signal_bus do
    name(:events)
  end

  topology do
    agent :planner, Worker do
      initial_state %{query: state(:query)}
    end

    agent :researchers, Worker do
      count state(:workers)
      initial_state %{query: state(:query)}
    end

    connections do
      connect("research.plan.request", from: :root, to: bus(:events))
      connect("research.work.request", from: :root, to: bus(:events))

      connect("research.plan.request", from: bus(:events), to: :planner)
      connect("research.work.request", from: :planner, to: bus(:events))

      connect("research.work.request",
        from: bus(:events),
        to: :researchers,
        delivery: :broadcast
      )

      connect("research.report.prepared", from: :researchers, to: bus(:events))
      connect("research.report.prepared", from: bus(:events), to: :root)
    end
  end
end

defmodule JidoTest.ComposableAgent.Definitions.Team.RecordReport do
  use Jido.Action,
    name: "agent_record_report",
    schema: Zoi.object(%{report: Zoi.string()})

  def run(%{report: report}, %{agent_state: state}) do
    {:ok, %{state | report: report},
     [Jido.Agent.Directive.emit("research.report.recorded", %{report: report})]}
  end
end

defmodule JidoTest.ComposableAgent.Definitions.Team.Worker do
  use Jido.Agent, name: "research_worker"

  state do
    schema Zoi.object(%{
             query: Zoi.string() |> Zoi.default(""),
             status: Zoi.string() |> Zoi.default("idle")
           })
  end

  routes do
    signal_source "/research/worker"

    route "research.work.request" do
      action %{query: query},
        schema: Zoi.object(%{query: Zoi.string()}),
        context: context do
        next_state = %{context.agent_state | query: query, status: "completed"}
        report = "Research findings for: #{query}"
        {:ok, next_state, [emit("research.report.prepared", %{report: report})]}
      end
    end

    route "research.plan.request" do
      action %{query: query},
        schema: Zoi.object(%{query: Zoi.string()}),
        context: context do
        next_state = %{context.agent_state | query: query, status: "planned"}
        {:ok, next_state, [emit("research.work.request", %{query: query})]}
      end
    end
  end
end
