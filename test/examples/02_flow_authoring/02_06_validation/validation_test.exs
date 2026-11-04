Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Compilation.ValidationTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("02_flow_authoring/02_06_validation/validation.ex")
    :ok
  end

  test "rejects missing result references and dependency cycles" do
    module = Jido.Examples.Compilation.Validation
    assert {:error, missing} = Jido.Flow.new(apply(module, :missing_result, []))
    assert missing.message == "Flow reference points to an unknown component"
    assert missing.details == %{owner: "save", component: "missing", path: [:components, 0]}
    assert {:error, cycle} = Jido.Flow.new(apply(module, :cycle, []))
    assert cycle.message == "flow dependency graph contains a cycle"
    assert cycle.details.components == ["first", "second"]
  end
end
