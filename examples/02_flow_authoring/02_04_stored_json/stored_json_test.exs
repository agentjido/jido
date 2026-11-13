Code.require_file("stored_json.ex", __DIR__)

defmodule Jido.Examples.Compilation.StoredJSONTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  setup do
    publication = :persistent_term.get({:jido, :catalog}, :not_ready)
    :persistent_term.erase({:jido, :catalog})

    on_exit(fn ->
      if publication == :not_ready,
        do: :persistent_term.erase({:jido, :catalog}),
        else: :persistent_term.put({:jido, :catalog}, publication)
    end)

    :ok
  end

  test "decodes trusted JSON to the exact canonical Flow without publication" do
    module = Jido.Examples.Compilation.StoredJSON
    assert {:ok, flow} = apply(module, :decode, [])
    assert flow == apply(module, :flow, [])
    assert Map.keys(flow.components) == ["echo"]
  end

  test "rejects an Action reference outside the Catalog" do
    module = Jido.Examples.Compilation.StoredJSON

    json =
      String.replace(
        apply(module, :document, []),
        "jido/examples/compilation/json_echo",
        "jido/examples/compilation/missing"
      )

    assert {:error, [issue]} = apply(module, :decode, [json])
    assert issue.code == :invalid_definition
    assert issue.message == "unknown flow catalog reference"
    assert issue.path == ["components", 0, "call", "target", "id"]
  end
end
