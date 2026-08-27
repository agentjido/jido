defmodule Jido.Agent.CanonicalAuthoringTest.SparkAgent do
  @moduledoc false

  use Jido.Agent,
    name: "canonical_spark_agent",
    description: "Canonical Agent parity"

  agent do
    state_schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))

    plugin(JidoTest.TestAgents.TestPluginWithRoutes,
      as: :support,
      config: %{token: "test"},
      metadata: %{owner: "spark"}
    )

    route("agent.tick", JidoTest.TestActions.NoSchema,
      params: %{amount: 1},
      priority: 3
    )

    schedule("tick", "*/5 * * * *", "agent.tick",
      data: %{amount: 1},
      metadata: %{owner: "spark"}
    )
  end
end

defmodule Jido.Agent.CanonicalAuthoringTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Builder
  alias Jido.Agent.CanonicalAuthoringTest.SparkAgent
  alias Jido.Agent.Plugin
  alias Jido.Agent.Schedule

  test "direct, Builder, and Spark authoring produce equal Agent definitions" do
    schema = Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})

    direct =
      Agent.new!(
        name: "canonical_spark_agent",
        description: "Canonical Agent parity",
        state_schema: schema,
        plugins: [
          Plugin.new!(
            module: JidoTest.TestAgents.TestPluginWithRoutes,
            as: :support,
            config: %{token: "test"},
            metadata: %{owner: "spark"}
          )
        ],
        routes: [
          {"agent.tick", JidoTest.TestActions.NoSchema, %{amount: 1}, 3}
        ],
        schedules: [
          Schedule.new!(
            name: "tick",
            cron_expression: "*/5 * * * *",
            signal_type: "agent.tick",
            data: %{amount: 1},
            metadata: %{owner: "spark"}
          )
        ]
      )

    built =
      Builder.new("canonical_spark_agent")
      |> Builder.description("Canonical Agent parity")
      |> Builder.state_schema(schema)
      |> Builder.plugin(JidoTest.TestAgents.TestPluginWithRoutes,
        as: :support,
        config: %{token: "test"},
        metadata: %{owner: "spark"}
      )
      |> Builder.route("agent.tick", JidoTest.TestActions.NoSchema,
        params: %{amount: 1},
        priority: 3
      )
      |> Builder.schedule("tick", "*/5 * * * *", "agent.tick",
        data: %{amount: 1},
        metadata: %{owner: "spark"}
      )
      |> Builder.build!()

    assert built == direct
    assert SparkAgent.agent() == direct
    assert Agent.semantic_identity(SparkAgent.agent()) == Agent.semantic_identity(direct)
  end
end
