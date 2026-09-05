defmodule JidoTest.Examples.DefinitionRevisionTest do
  use JidoTest.Case, async: false
  @moduletag :example
  alias Jido.Examples.DefinitionRevision, as: Example

  setup do
    module = Example.install(1)
    on_exit(&Example.unload/0)

    {:ok, checkpoint} =
      Jido.Agent.checkpoint(apply(module, :new!, [[id: "cart", state: %{total: 20}]]))

    %{module: module, checkpoint: checkpoint}
  end

  test "the same definition restores the complete saved state", c do
    assert {:ok, restored} = Jido.Agent.restore(c.module, c.checkpoint)
    assert restored.state == %{total: 20}
    assert restored.metadata.definition_revision == 1
  end

  test "a new definition revision is rejected even when the saved state remains valid", c do
    assert Example.install(2) == c.module
    assert c.module.definition_revision() == 2
    assert {:error, _revision_mismatch} = Jido.Agent.restore(c.module, c.checkpoint)
  end
end
