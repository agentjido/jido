defmodule JidoTest.Contract.AgentViewTest do
  use Covenant.Case, component: "jido.agent", async: true

  alias Jido.Agent
  alias Jido.Agent.View
  alias Jido.Authoring.{Document, Registry}
  alias JidoTest.AgentFixtures.{Add, CounterAgent}
  alias JidoTest.AgentContract, as: F

  defp registry do
    Registry.new!(%{
      {"agents/counter", 1} => {:agent, CounterAgent},
      {"agents/core", 1} => {:agent, Agent},
      {"schemas/counter", 1} => {:schema, CounterAgent.definition().schema},
      {"schemas/empty", 1} => {:schema, Zoi.object(%{})},
      {"actions/add", 1} => {:action, Add},
      {"flows/contract", 1} => {:flow, F.Flow}
    })
  end

  def transform(value), do: value

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
                   "target" => %{"id" => "actions/add", "vsn" => 1}
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
  test "operation limits keep their documented default and inclusive bounds" do
    routes =
      for index <- 1..501 do
        %{path: "operation.#{index}", handler: %{kind: :action, target: Add}}
      end

    definition = Agent.define!(%{name: "view_limits", routes: routes})

    assert {:ok, default_view} = View.project(definition, registry())
    assert length(default_view["operations"]["items"]) == 100

    assert {:ok, zero_view} = View.project(definition, registry(), operation_limit: 0)
    assert zero_view["operations"]["items"] == []

    assert {:ok, maximum_view} = View.project(definition, registry(), operation_limit: 500)
    assert length(maximum_view["operations"]["items"]) == 500

    for invalid <- [-1, 501] do
      assert {:error, %{message: message}} =
               View.project(definition, registry(), operation_limit: invalid)

      assert is_binary(message) and message != ""
    end

    exact = Agent.define!(%{name: "exact_limit", routes: Enum.take(routes, 2)})
    assert {:ok, exact_view} = View.project(exact, registry(), operation_limit: 2)
    refute exact_view["operations"]["truncated"]
  end

  @tag obligation: "jido.agent.I31"
  test "operation summaries expose Action, Flow, transform, and forward targets" do
    definition =
      Agent.define!(%{
        name: "view_handlers",
        routes: [
          %{path: "flow.run", handler: %{kind: :flow, target: F.Flow}},
          %{
            path: "transform.run",
            handler: %{kind: :transform, target: {__MODULE__, :transform, 1}}
          },
          %{path: "forward.run", handler: %{kind: :forward, target: %{kind: :parent}}}
        ]
      })

    assert {:ok, view} = View.project(definition, registry())
    [flow, transform, forward] = view["operations"]["items"]
    assert flow["target"] == %{"id" => "flows/contract", "vsn" => 1}
    assert transform["target"] == nil
    assert forward["target"] == %{"kind" => "parent"}
  end

  @tag obligation: "jido.agent.I31"
  test "unsupported view sources return a structured nonempty error" do
    assert {:error, %{details: %{}, message: message}} = View.project(nil, registry())
    assert is_binary(message) and message != ""
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
