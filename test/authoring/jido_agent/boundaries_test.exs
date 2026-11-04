Code.require_file("../support/jido_agent/composable_compiler.exs", __DIR__)

defmodule Jido.Agent.Authoring.BoundariesTest do
  use ExUnit.Case, async: true
  @moduletag :authoring
  alias Jido.Agent
  alias Jido.Test.Agent.Authoring.Compiler

  defmodule Work do
    use Jido.Action,
      name: "authoring_boundary_work"

    def run(input, _context), do: {:ok, input}
  end

  test "removed core forms cannot enter a definition" do
    for attrs <- [
          %{schedules: []},
          %{kind: :definition},
          %{definition: %{name: "nested"}},
          %{topology: %{groups: []}},
          %{topology: %{exports: []}},
          %{topology: %{relationships: []}}
        ] do
      assert {:error, _} = Agent.define(Map.merge(%{name: "old"}, attrs))
    end
  end

  test "helper construction preserves input and uses an explicit source" do
    module =
      Compiler.compile(
        "routes do\nsignal_source \"/boundary\"\nroute \"work.request\", #{inspect(Work)}, as: :work\nend"
      )

    assert {:ok, first} = module.work_signal(%{items: []})
    assert {:ok, second} = module.work_signal(%{items: []})
    assert first.id != second.id
    assert first.type == "work.request"
    assert first.source == "/boundary"
    assert first.data === %{items: []}
    assert {:ok, explicit} = module.work_signal(%{}, source: "/caller")
    assert explicit.source == "/caller"
  end

  test "JSON round trips require the supplied Registry" do
    definition = Agent.define!(%{name: "no_json"})
    registry = Jido.Test.AgentServer.Registry.for(definition)
    assert {:ok, document} = Jido.Test.AgentServer.Registry.encode(definition, registry)
    assert {:ok, ^definition} = Jido.Test.AgentServer.Registry.decode(document, registry)

    assert_raise ArgumentError, "Catalog is invalid: %{}", fn ->
      Jido.Test.AgentServer.Registry.decode(document, %{})
    end
  end
end
