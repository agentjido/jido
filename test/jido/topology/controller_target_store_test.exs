defmodule Jido.Topology.Controller.TargetStoreTest do
  use ExUnit.Case, async: true

  alias Jido.Examples.Topology.Cell
  alias Jido.Topology.Builder
  alias Jido.Topology.Controller.TargetStore

  defmodule IndeterminateAdapter do
    @behaviour Jido.Persistence.Adapter

    @impl true
    def get(_key, _opts), do: {:error, :not_found}

    @impl true
    def compare_and_swap(_key, _expected, _value, _opts), do: {:error, :indeterminate}
  end

  test "accepted target revisions survive a fresh read and reject stale updates" do
    suffix = System.unique_integer([:positive])
    jido = :"target_store_#{suffix}"
    table = :"target_store_table_#{suffix}"

    start_supervised!(
      {Jido,
       name: jido,
       namespace: Atom.to_string(jido),
       persistence: {Jido.Persistence.ETS, table: table}}
    )

    initial = topology("target-store", 1)
    target = topology(initial.id, 2)

    assert {:ok, ^initial, 0, %{}} = TargetStore.load(jido, initial)
    assert {:ok, 1} = TargetStore.accept(jido, 0, target, %{})
    assert {:ok, ^target, 1, %{}} = TargetStore.load(jido, initial)
    assert {:error, :conflict} = TargetStore.accept(jido, 0, target, %{})

    key = target.plan.agents |> Map.keys() |> hd()
    placement = %{key => node()}
    expanded = topology(initial.id, 3)
    assert {:ok, 2} = TargetStore.accept(jido, 1, expanded, placement)
    assert {:ok, ^expanded, 2, ^placement} = TargetStore.load(jido, initial)

    assert {:error, {:nonportable_topology_target, _}} =
             TargetStore.accept(jido, 2, %{expanded | input: %{pid: self()}}, placement)
  end

  test "uncertain target write has an explicit indeterminate result" do
    jido = :"target_store_fault_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido, persistence: IndeterminateAdapter})
    target = topology("target-fault", 1)

    assert {:error, {:indeterminate, _}} = TargetStore.accept(jido, 0, target, %{})
  end

  defp topology(id, count) do
    Builder.new(name: "target_store")
    |> Builder.group(:workers, Cell, count: count)
    |> Builder.build!(id: id)
  end
end
