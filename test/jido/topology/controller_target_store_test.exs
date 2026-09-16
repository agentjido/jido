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

  defmodule TokenAdapter do
    @behaviour Jido.Persistence.Adapter

    @impl true
    def get(key, opts) do
      Elixir.Agent.get(Keyword.fetch!(opts, :owner), fn values ->
        case Map.fetch(values, key) do
          :error -> {:error, :not_found}
          {:ok, {bytes, token}} -> {:ok, bytes, token}
        end
      end)
    end

    @impl true
    def compare_and_swap(key, expected, bytes, opts) do
      send(Keyword.fetch!(opts, :observer), {:topology_cas, expected})

      Elixir.Agent.get_and_update(Keyword.fetch!(opts, :owner), fn values ->
        current = Map.get(values, key)

        if (expected == :not_found and is_nil(current)) or
             (match?({:token, _}, expected) and is_tuple(current) and
                elem(expected, 1) == elem(current, 1)) do
          token = "target-#{System.unique_integer([:positive])}"
          {:ok, Map.put(values, key, {bytes, token})}
        else
          {{:error, :conflict}, values}
        end
      end)
    end
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

    assert {:ok, ^initial, 0, %{}, nil} = TargetStore.load(jido, initial)
    assert {:ok, 1} = TargetStore.accept(jido, 0, target, %{})
    assert {:ok, ^target, 1, %{}, nil} = TargetStore.load(jido, initial)
    assert {:error, :conflict} = TargetStore.accept(jido, 0, target, %{})

    key = target.plan.agents |> Map.keys() |> hd()
    placement = %{key => node()}
    expanded = topology(initial.id, 3)
    assert {:ok, 2} = TargetStore.accept(jido, 1, expanded, placement)
    assert {:ok, ^expanded, 2, ^placement, nil} = TargetStore.load(jido, initial)

    other_node = :"pending-placement@127.0.0.1"
    move = %{key: key, from: node(), to: other_node}
    moved = %{key => other_node}
    assert {:ok, 3} = TargetStore.accept_placement(jido, 2, expanded, moved, move)
    assert {:ok, ^expanded, 3, ^moved, ^move} = TargetStore.load(jido, initial)
    assert {:ok, 4} = TargetStore.complete_placement(jido, 3, expanded, moved)
    assert {:ok, ^expanded, 4, ^moved, nil} = TargetStore.load(jido, initial)

    assert {:error, {:nonportable_topology_target, _}} =
             TargetStore.accept(jido, 4, %{expanded | input: %{pid: self()}}, placement)
  end

  test "uncertain target write has an explicit indeterminate result" do
    jido = :"target_store_fault_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido, persistence: IndeterminateAdapter})
    target = topology("target-fault", 1)

    assert {:error, {:indeterminate, _}} = TargetStore.accept(jido, 0, target, %{})
  end

  test "target revisions use the opaque condition from the shared Store" do
    {:ok, owner} = Elixir.Agent.start_link(fn -> %{} end)
    on_exit(fn -> if Process.alive?(owner), do: Elixir.Agent.stop(owner) end)

    jido = :"target_store_token_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Jido, name: jido, persistence: {TokenAdapter, owner: owner, observer: self()}}
    )

    initial = topology("target-token", 1)
    target = topology(initial.id, 2)
    next = topology(initial.id, 3)

    assert {:ok, 1} = TargetStore.accept(jido, 0, target, %{})
    assert_received {:topology_cas, :not_found}
    assert {:ok, ^target, 1, %{}, nil} = TargetStore.load(jido, initial)
    assert {:ok, 2} = TargetStore.accept(jido, 1, next, %{})
    assert_received {:topology_cas, {:token, token}}
    assert is_binary(token)
    assert {:ok, ^next, 2, %{}, nil} = TargetStore.load(jido, initial)
  end

  defp topology(id, count) do
    Builder.new(name: "target_store")
    |> Builder.group(:workers, Cell, count: count)
    |> Builder.build!(id: id)
  end
end
