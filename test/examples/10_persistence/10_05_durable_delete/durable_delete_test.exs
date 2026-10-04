defmodule JidoTest.Examples.Persistence.DurableDeleteTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.Examples.DurableDelete
  alias Jido.Persistence.ETS
  alias JidoTest.Persistence.ProbeStore

  setup do
    store = {ProbeStore, store: start_supervised!(ProbeStore)}
    order = DurableDelete.new!(id: "order")

    :ok =
      Jido.Persistence.save_agent(store, order, namespace: "durable-delete-example", revision: 0)

    %{store: store, order: order}
  end

  test "revision checks reject a stale writer while the record exists", c do
    assert :ok =
             Jido.Persistence.save_agent(c.store, c.order,
               namespace: "durable-delete-example",
               revision: 2,
               expected_revision: 0
             )

    assert {:error, :conflict} = DurableDelete.delayed_write(c.store, c.order)

    assert {:ok, _, 2} =
             Jido.Persistence.load_agent_with_revision(c.store, DurableDelete, c.order.id,
               namespace: "durable-delete-example"
             )
  end

  test "deletion makes the order unavailable", c do
    assert :ok =
             Jido.Persistence.delete_agent(c.store, DurableDelete, c.order.id,
               namespace: "durable-delete-example"
             )

    assert {:error, :deleted} =
             Jido.Persistence.load_agent(c.store, DurableDelete, c.order.id,
               namespace: "durable-delete-example"
             )
  end

  test "a delayed initial writer cannot restore a deleted order", c do
    assert :ok =
             Jido.Persistence.delete_agent(c.store, DurableDelete, c.order.id,
               namespace: "durable-delete-example"
             )

    assert {:error, :conflict} = DurableDelete.delayed_write(c.store, c.order)

    assert {:error, :deleted} =
             Jido.Persistence.load_agent(c.store, DurableDelete, c.order.id,
               namespace: "durable-delete-example"
             )
  end

  test "the local adapter compare-and-swap condition uses exact bytes" do
    table = :"durable_delete_cas_#{System.unique_integer([:positive])}"
    opts = [table: table]
    on_exit(fn -> ETS.delete("record", opts) end)

    assert :ok = ETS.compare_and_swap("record", :not_found, <<0, 255>>, opts)
    assert {:error, :conflict} = ETS.compare_and_swap("record", <<0>>, <<1>>, opts)
    assert {:ok, <<0, 255>>} = ETS.get("record", opts)
    assert :ok = ETS.compare_and_swap("record", <<0, 255>>, <<1>>, opts)
    assert {:ok, <<1>>} = ETS.get("record", opts)
  end
end
