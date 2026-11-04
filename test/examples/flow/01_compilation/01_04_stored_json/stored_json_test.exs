Code.require_file("../../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Compilation.StoredJSONTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("flow/01_compilation/01_04_stored_json/stored_json.ex")
    :ok
  end

  test "decodes trusted JSON to the exact canonical Flow" do
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
