Code.require_file("../../support/loader.exs", __DIR__)

JidoTest.Examples.Loader.require_source!("15_ai_basics/15_09_json_agent/json_agent.ex")

defmodule JidoTest.Examples.AI.JSONAgentTest do
  use JidoTest.Case, async: true

  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("15_ai_basics/15_09_json_agent/json_agent.ex")
    :ok
  end

  alias Jido.Examples.AI.JSONAgent

  test "the checked-in document restores the graph-first definition" do
    assert {:ok, definition} = JSONAgent.import()
    assert definition == JSONAgent.definition()
    assert [%{handler: %{target: Jido.AI.Reasoning.ReAct}}] = definition.routes

    assert {:ok, %{workflow: %Runic.Workflow{}}} =
             Jido.AI.Reasoning.preflight(definition.module, %{input: "Inspect this"})
  end

  test "current encoding round-trips through JSON" do
    assert {:ok, json} = JSONAgent.encode_json()

    assert {:ok, definition} =
             Jido.Codec.decode_json(json,
               catalog: JSONAgent.registry(),
               codec: Jido.Agent.Codec
             )

    assert definition == JSONAgent.definition()
  end

  test "an untrusted catalog cannot resolve the document" do
    assert {:error, _} =
             Jido.Codec.decode_json(JSONAgent.fixture_json(),
               catalog: Jido.Catalog.new!([]),
               codec: Jido.Agent.Codec
             )
  end
end
