defmodule JidoTest.Contract.AgentViewTest do
  use Covenant.Case, component: "jido.agent", async: true

  alias Jido.Agent
  alias Jido.Agent.View
  alias Jido.Authoring.{Document, Registry}
  alias JidoTest.AgentFixtures.{Add, CounterAgent}

  defp registry do
    Registry.new!(%{
      {"agents/counter", 1} => {:agent, CounterAgent},
      {"agents/core", 1} => {:agent, Agent},
      {"schemas/counter", 1} => {:schema, CounterAgent.definition().schema},
      {"schemas/empty", 1} => {:schema, Zoi.object(%{})},
      {"actions/add", 1} => {:action, Add}
    })
  end

  @tag obligation: "jido.agent.I31"
  test "compiled and data Agent definitions use one JSON view contract" do
    assert {:ok, compiled} = View.project(CounterAgent, registry())
    assert {:ok, from_definition} = View.project(CounterAgent.definition(), registry())
    assert compiled == from_definition

    data =
      Agent.define!(%{
        name: "data_counter",
        description: "A stored counter",
        metadata: %{"private" => "do not expose"},
        routes: [
          %{path: "counter.add", handler: %{kind: :action, target: Add}, defaults: %{by: 3}}
        ]
      })

    assert {:ok, view} = View.project(data, registry())

    assert view == %{
             "type" => "jido.agent.view",
             "vsn" => 1,
             "id" => nil,
             "name" => "data_counter",
             "description" => "A stored counter",
             "definition_vsn" => 1,
             "agent_type" => nil,
             "schema" => %{"id" => "schemas/empty", "vsn" => 1},
             "operations" => %{
               "items" => [
                 %{
                   "signal_type" => "counter.add",
                   "kind" => "action",
                   "target" => %{"id" => "actions/add", "vsn" => 1},
                   "emits" => nil
                 }
               ],
               "total" => 1,
               "truncated" => false
             }
           }

    assert :ok = Document.check(view)
    refute inspect(view) =~ "do not expose"
    refute inspect(view) =~ inspect(Add)
    refute Map.has_key?(view, "metadata")
  end

  @tag obligation: "jido.agent.I31"
  test "an instance exposes identity but not state" do
    instance = CounterAgent.instantiate!(id: "alice", state: %{count: 4})

    assert {:ok, view} = View.project(instance, registry())
    assert view["id"] == "alice"
    refute Map.has_key?(view, "state")
  end

  @tag obligation: "jido.agent.I31"
  test "operation output is bounded and reports truncation" do
    definition =
      Agent.define!(%{
        name: "bounded",
        routes: [
          %{path: "counter.one", handler: %{kind: :action, target: Add}},
          %{path: "counter.two", handler: %{kind: :action, target: Add}}
        ]
      })

    assert {:ok, view} = View.project(definition, registry(), operation_limit: 1)
    assert %{"total" => 2, "truncated" => true, "items" => [item]} = view["operations"]
    assert item["signal_type"] == "counter.one"

    assert {:error, %{__exception__: true}} =
             View.project(definition, registry(), operation_limit: 501)
  end

  @tag obligation: "jido.agent.I31"
  test "operation limits also bound Registry resolution work" do
    definition =
      Agent.define!(%{
        name: "bounded_resolution",
        routes: [
          %{path: "counter.one", handler: %{kind: :action, target: Add}},
          %{
            path: "counter.two",
            handler: %{kind: :action, target: JidoTest.TestActions.BasicAction}
          }
        ]
      })

    assert {:ok, view} = View.project(definition, registry(), operation_limit: 1)
    assert %{"total" => 2, "truncated" => true, "items" => [_]} = view["operations"]
  end

  @tag obligation: "jido.agent.I31"
  test "projection requires identifiers for every exposed code value" do
    definition = CounterAgent.definition()

    stable_without_action =
      Registry.new!(%{
        {"agents/counter", 1} => {:agent, CounterAgent},
        {"schemas/counter", 1} => {:schema, CounterAgent.definition().schema}
      })

    assert {:error, %{message: message}} = View.project(definition, stable_without_action)
    assert message =~ "no reference"
  end
end
