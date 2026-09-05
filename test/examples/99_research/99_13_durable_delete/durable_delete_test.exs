defmodule JidoTest.Examples.DurableDeleteTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.Examples.{DurableDelete, PersistenceProbeStore}

  setup do
    store = {PersistenceProbeStore, store: start_supervised!(PersistenceProbeStore)}
    order = DurableDelete.new!(id: "order")
    :ok = Jido.Persistence.save_agent(store, order, revision: 0)
    %{store: store, order: order}
  end

  test "revision checks reject a stale writer while the record exists", c do
    assert :ok = Jido.Persistence.save_agent(c.store, c.order, revision: 2, expected_revision: 0)
    assert {:error, :conflict} = DurableDelete.delayed_write(c.store, c.order)

    assert {:ok, _, 2} =
             Jido.Persistence.load_agent_with_revision(c.store, DurableDelete, c.order.id)
  end

  test "deletion makes the order unavailable", c do
    assert :ok = Jido.Persistence.delete_agent(c.store, DurableDelete, c.order.id)
    assert {:error, :not_found} = Jido.Persistence.load_agent(c.store, DurableDelete, c.order.id)
  end

  test "a delayed initial writer cannot restore a deleted order", c do
    assert :ok = Jido.Persistence.delete_agent(c.store, DurableDelete, c.order.id)
    assert {:error, _deleted_or_conflict} = DurableDelete.delayed_write(c.store, c.order)
    assert {:error, _} = Jido.Persistence.load_agent(c.store, DurableDelete, c.order.id)
  end
end
