Code.require_file("support/jido_agent/composable_fixtures.exs", __DIR__)

defmodule Jido.Authoring.AgentEquivalenceTest do
  use ExUnit.Case, async: true
  @moduletag :authoring

  alias Jido.Agent
  alias Jido.Test.Agent.Authoring.{Action, Audit, Flow, Worker}

  defmodule Complete do
    use Jido.Agent,
      name: "authoring_complete_agent",
      description: "Complete authoring reference",
      vsn: 2,
      metadata: %{enabled: false, count: 0, note: nil},
      plugins: [{Jido.Test.Agent.Authoring.Audit, %{enabled: false}}]

    state do
      schema Jido.Joi.object(%{
               value: Jido.Joi.string() |> Jido.Joi.default("initial"),
               count: Jido.Joi.integer() |> Jido.Joi.default(0)
             })

      initial_state %{value: "seed", count: 0}
    end

    routes do
      signal_source "/authoring/complete"

      route "work.request", Jido.Test.Agent.Authoring.Action,
        as: :work,
        defaults: %{value: "default"}

      route "plan.request", Jido.Test.Agent.Authoring.Flow
    end

    audit do
      label("reference")
    end

    topology do
      agent :worker, Jido.Test.Agent.Authoring.Worker,
        count: 2,
        initial_state: %{value: "child"}
    end
  end

  test "DSL, independent Map, and fixed JSON produce the same complete Agent definition" do
    expected = Complete.definition()
    from_map = Agent.define!(complete_map())
    catalog = Jido.Test.AgentServer.Registry.for(expected)
    fixture = Path.join(__DIR__, "support/complete_agent.json")
    json = File.read!(fixture)

    assert from_map === expected
    assert {:ok, from_json} = Jido.Test.AgentServer.Registry.decode_json(json, catalog)
    assert from_json === expected

    assert {:ok, encoded} = Jido.Test.AgentServer.Registry.encode_json(expected, catalog)
    assert Jason.decode!(encoded) === Jason.decode!(json)
  end

  defp complete_map do
    %{
      module: Complete,
      name: "authoring_complete_agent",
      description: "Complete authoring reference",
      vsn: 2,
      metadata: %{enabled: false, count: 0, note: nil},
      schema:
        Jido.Joi.object(%{
          value: Jido.Joi.string() |> Jido.Joi.default("initial"),
          count: Jido.Joi.integer() |> Jido.Joi.default(0)
        }),
      initial_state: %{value: "seed", count: 0},
      signal_source: "/authoring/complete",
      routes: [
        %{
          path: "work.request",
          as: :work,
          defaults: %{value: "default"},
          handler: %{kind: :action, target: Action},
          state: %{source: :output, path: []}
        },
        %{
          path: "plan.request",
          handler: %{kind: :flow, target: Flow},
          state: %{source: :output, path: []}
        }
      ],
      topology: %{
        agents: [
          %{name: :worker, definition: Worker, count: 2, initial_state: %{value: "child"}}
        ],
        connections: []
      },
      plugins: [
        %{id: Audit.id(), provider: Audit, vsn: Audit.vsn(), data: %{label: "reference", enabled: false}}
      ]
    }
  end
end
