Code.require_file("json_agent.ex", __DIR__)

defmodule Jido.Examples.AI.JSONAgentTest do
  use Jido.Test.Case, async: true

  @moduletag :integration

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
