Code.require_file("persistence_selection.ex", __DIR__)

defmodule Jido.Examples.Operations.PersistenceSelectionTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Jido.Examples.Operations.PersistenceSelection

  test "explicit, disabled, and inherited adapter selection stay distinct" do
    suffix = System.unique_integer([:positive])
    table = :"operations_persistence_#{suffix}"
    config = {Jido.Persistence.ETS, table: table}

    assert {:ok, ^config} = PersistenceSelection.explicit(config)
    assert {:ok, nil} = PersistenceSelection.explicit(nil)

    instance = :"operations_persistence_instance_#{suffix}"

    start_supervised!(
      {Jido, name: instance, namespace: "examples/operations/persistence/#{suffix}", persistence: config},
      id: instance
    )

    assert {:ok, ^config} = PersistenceSelection.inherited(instance)
    assert {:error, _reason} = PersistenceSelection.explicit({String, []})
  end
end
