Code.require_file("public_agent_view.ex", __DIR__)

defmodule Jido.Examples.PublicAgentViewTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.PublicAgentView
  alias Jido.Examples.PublicAgentView.Agent

  test "a view exposes public operations but not state or private definition data" do
    instance = Agent.instantiate!(id: "document-7", state: %{title: "secret draft"})
    assert {:ok, view} = PublicAgentView.project(instance)

    assert view["id"] == "document-7"
    assert view["name"] == "public_agent_view"
    assert view["agent_type"] == %{"id" => "examples/agent-view/agent", "vsn" => 1}
    assert view["operations"]["total"] == 1

    text = inspect(view)
    refute text =~ "secret draft"
    refute text =~ "private-default"
    refute text =~ "internal_owner"
    refute Map.has_key?(view, "state")
    assert :ok = Jido.Codec.Document.check_json(view, 32_000)
  end

  test "operation limits are explicit and report truncation" do
    assert {:ok, view} = PublicAgentView.project(Agent, operation_limit: 0)
    assert view["operations"] == %{"items" => [], "total" => 1, "truncated" => true}
  end
end
