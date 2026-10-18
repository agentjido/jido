Code.require_file("../support/agents/composable_compiler.exs", __DIR__)

defmodule JidoTest.Authoring.Agents.MetadataTest do
  use ExUnit.Case, async: true
  @moduletag :authoring
  alias Jido.Agent
  alias JidoTest.ComposableAgent.Compiler

  test "metadata preserves atom, string, mixed keys and static values in Map and DSL" do
    for metadata <- [
          %{case: "atom"},
          %{"case" => "string"},
          %{"case" => "string", :case => "atom", :nested => %{enabled: false}},
          %{date: ~D[2026-09-13], tuple: {:ok, 1.0}}
        ] do
      module = Compiler.compile("agent do metadata #{inspect(metadata)} end")
      expected = Agent.define!(%{name: "generated", module: module, metadata: metadata})
      assert module.definition() === expected
      assert expected.metadata === metadata
      assert Agent.definition(Agent.instantiate!(expected, id: "one")) === expected
    end
  end

  test "metadata rejects structs, non-Map values and live values" do
    for metadata <- [
          ~D[2026-09-13],
          nil,
          false,
          42,
          "invalid",
          [],
          [case: "invalid"],
          %{pid: self()},
          %{callback: fn -> :ok end}
        ] do
      assert {:error, _} = Agent.define(%{name: "invalid", metadata: metadata})
    end
  end
end
