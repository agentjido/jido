defmodule JidoTest.Persistence.MnesiaTest do
  use ExUnit.Case, async: false

  alias Jido.Persistence
  alias Jido.Persistence.{Mnesia, Store}
  alias JidoTest.Persistence.AdapterConformance
  alias JidoTest.AgentRuntimeFixtures.RuntimeAgent

  setup do
    {:ok, _started} = Application.ensure_all_started(:mnesia)
    table = :"jido_persistence_mnesia_#{System.unique_integer([:positive])}"

    assert {:atomic, :ok} =
             :mnesia.create_table(table, attributes: [:key, :value], ram_copies: [node()])

    on_exit(fn -> assert {:atomic, :ok} = :mnesia.delete_table(table) end)
    %{table: table, opts: [table: table]}
  end

  test "obeys the binary read and atomic CAS contract", %{opts: opts} do
    assert :ok = AdapterConformance.assert_binary_get_and_cas(Mnesia, opts, :mnesia)
  end

  test "works through the shared Store and supports explicit maintenance", %{opts: opts} do
    assert {:ok, store} = Store.open({Mnesia, opts})
    assert {:error, :not_found} = Store.read(store, "record")
    assert :ok = Store.compare_and_swap(store, "record", :not_found, <<0, 255>>)
    assert {:ok, <<0, 255>>, <<0, 255>>} = Store.read(store, "record")

    assert :ok = Mnesia.put("record", "maintenance", opts)
    assert {:ok, "maintenance"} = Mnesia.get("record", opts)
    assert :ok = Mnesia.delete("record", opts)
    assert {:error, :not_found} = Mnesia.get("record", opts)
  end

  test "saves, loads, and tombstones an Agent checkpoint", %{opts: opts} do
    source = {Mnesia, opts}
    agent = RuntimeAgent.new!(id: "mnesia-checkpoint")

    assert :ok = Persistence.save_agent(source, agent)
    assert {:ok, ^agent} = Persistence.load_agent(source, RuntimeAgent, agent.id)
    assert :ok = Persistence.delete_agent(source, RuntimeAgent, agent.id)
    assert {:error, :deleted} = Persistence.load_agent(source, RuntimeAgent, agent.id)
  end

  test "requires an existing non-local set table with two attributes", %{table: table} do
    assert :ok = Mnesia.validate_options(table: table)
    assert {:error, :invalid_mnesia_options} = Mnesia.validate_options([])
    assert {:error, :invalid_mnesia_options} = Mnesia.validate_options(table: "bad")
    missing = :"#{table}_missing"
    assert {:error, _reason} = Mnesia.validate_options(table: missing)
    refute missing in :mnesia.system_info(:tables)

    local = :"#{table}_local"

    assert {:atomic, :ok} =
             :mnesia.create_table(local, attributes: [:key, :value], local_content: true)

    on_exit(fn -> assert {:atomic, :ok} = :mnesia.delete_table(local) end)
    assert {:error, :invalid_mnesia_options} = Mnesia.validate_options(table: local)

    bag = :"#{table}_bag"
    assert {:atomic, :ok} = :mnesia.create_table(bag, attributes: [:key, :value], type: :bag)
    on_exit(fn -> assert {:atomic, :ok} = :mnesia.delete_table(bag) end)
    assert {:error, :invalid_mnesia_options} = Mnesia.validate_options(table: bag)

    wrong_attributes = :"#{table}_wrong_attributes"

    assert {:atomic, :ok} =
             :mnesia.create_table(wrong_attributes, attributes: [:key, :payload])

    on_exit(fn -> assert {:atomic, :ok} = :mnesia.delete_table(wrong_attributes) end)

    assert {:error, :invalid_mnesia_options} =
             Mnesia.validate_options(table: wrong_attributes)
  end

  test "rejects a nested transaction before a write starts", %{opts: opts} do
    assert {:atomic, {:error, {:rejected, :nested_transaction}}} =
             :mnesia.transaction(fn ->
               Mnesia.compare_and_swap("nested", :not_found, "value", opts)
             end)

    assert {:error, :not_found} = Mnesia.get("nested", opts)
  end

  test "a storage abort is an indeterminate Store result", %{table: table, opts: opts} do
    assert {:ok, store} = Store.open({Mnesia, opts})
    assert {:atomic, :ok} = :mnesia.change_table_access_mode(table, :read_only)

    assert {:error, {:indeterminate, {:mnesia_aborted, _reason}}} =
             Store.compare_and_swap(store, "record", :not_found, "value")

    assert {:error, :not_found} = Store.read(store, "record")
    assert {:atomic, :ok} = :mnesia.change_table_access_mode(table, :read_write)
  end
end
