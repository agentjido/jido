defmodule Jido.Agent.ViewTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.View
  alias Jido.Codec.{Data, Registry}
  alias JidoTest.AgentFixtures.{Add, CounterAgent}

  defp registry do
    Registry.new!(%{
      "agents/counter/v1" => {:agent, CounterAgent},
      "agents/core/v1" => {:agent, Agent},
      "schemas/counter/v1" => {:schema, CounterAgent.domain_schema()},
      "schemas/empty/v1" => {:schema, Zoi.object(%{})},
      "actions/add/v1" => {:action, Add}
    })
  end

  test "compiled and data Agent definitions use one JSON view contract" do
    assert {:ok, compiled} = View.project(CounterAgent, registry())
    assert {:ok, from_definition} = View.project(CounterAgent.definition(), registry())
    assert compiled == from_definition

    data =
      Agent.new!(
        name: "data_counter",
        description: "A stored counter",
        metadata: %{"private" => "do not expose"},
        routes: [{"counter.add", {Add, %{by: 3}}}]
      )

    assert {:ok, view} = View.project(data, registry())

    assert view == %{
             "type" => "jido.agent.view",
             "version" => 1,
             "id" => nil,
             "name" => "data_counter",
             "description" => "A stored counter",
             "definition_vsn" => nil,
             "agent_type_id" => "agents/core/v1",
             "schema_id" => "schemas/empty/v1",
             "operations" => %{
               "items" => [
                 %{
                   "signal_type" => "counter.add",
                   "kind" => "action",
                   "target_id" => "actions/add/v1",
                   "priority" => 0
                 }
               ],
               "total" => 1,
               "truncated" => false
             }
           }

    assert :ok = Data.check_document(view)
    refute inspect(view) =~ "do not expose"
    refute inspect(view) =~ inspect(Add)
    refute Map.has_key?(view, "metadata")
  end

  test "an instance exposes identity but not state" do
    instance = CounterAgent.new!(id: "alice", state: %{count: 4})

    assert {:ok, view} = View.project(instance, registry())
    assert view["id"] == "alice"
    refute Map.has_key?(view, "state")
  end

  test "operation output is bounded and reports truncation" do
    definition =
      Agent.new!(
        name: "bounded",
        routes: [
          {"counter.one", Add},
          {"counter.two", Add}
        ]
      )

    assert {:ok, view} = View.project(definition, registry(), operation_limit: 1)
    assert %{"total" => 2, "truncated" => true, "items" => [item]} = view["operations"]
    assert item["signal_type"] == "counter.one"

    assert {:error, %Jido.Error.ValidationError{}} =
             View.project(definition, registry(), operation_limit: 501)
  end

  test "operation limits also bound Registry resolution work" do
    definition =
      Agent.new!(
        name: "bounded_resolution",
        routes: [
          {"counter.one", Add},
          {"counter.two", JidoTest.TestActions.BasicAction}
        ]
      )

    assert {:ok, view} = View.project(definition, registry(), operation_limit: 1)
    assert %{"total" => 2, "truncated" => true, "items" => [_]} = view["operations"]
  end

  test "projection requires stable identifiers for every exposed code value" do
    definition = CounterAgent.definition()
    assert {:ok, _document, temporary} = Agent.Codec.encode(definition)

    assert {:error, %Jido.Error.ValidationError{message: message}} =
             View.project(definition, temporary)

    assert message =~ "stable Registry"

    stable_without_action =
      Registry.new!(%{
        "agents/counter/v1" => {:agent, CounterAgent},
        "schemas/counter/v1" => {:schema, CounterAgent.domain_schema()}
      })

    assert {:error, %Jido.Error.ValidationError{message: message}} =
             View.project(definition, stable_without_action)

    assert message =~ "no identifier"
  end
end
