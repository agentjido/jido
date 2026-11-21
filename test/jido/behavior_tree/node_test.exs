defmodule Jido.BehaviorTree.NodeTest do
  use ExUnit.Case, async: true

  alias Jido.BehaviorTree.{Node, Tick}
  alias Jido.BehaviorTree.Test.Nodes.SimpleNode

  defmodule ContextNode do
    @schema Zoi.struct(
              __MODULE__,
              %{
                value: Zoi.integer() |> Zoi.default(0)
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @behaviour Jido.BehaviorTree.Node

    def tick(%__MODULE__{} = state, _tick), do: {:success, state}
    def halt(%__MODULE__{} = state), do: state

    def tick_with_context(%__MODULE__{} = state, tick) do
      updated_tick = Tick.put(tick, :context_node, true)
      {:success, %{state | value: state.value + 1}, updated_tick}
    end
  end

  defmodule RaisingNode do
    @schema Zoi.struct(__MODULE__, %{}, coerce: true)
    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @behaviour Jido.BehaviorTree.Node

    def tick(_state, _tick), do: raise("tick explosion")
    def halt(_state), do: raise("halt explosion")
  end

  test "execute_tick/2 runs node tick callback" do
    tick = Tick.new()
    node = SimpleNode.new("tick")

    {status, updated_node} = Node.execute_tick(node, tick)

    assert status == :success
    assert updated_node.tick_count == 1
  end

  test "execute_tick/2 converts raised exceptions to node errors" do
    tick = Tick.new()
    node = %RaisingNode{}

    {status, same_node} = Node.execute_tick(node, tick)

    assert {:error, error} = status
    assert %Jido.BehaviorTree.Error.BehaviorTreeError{} = error
    assert same_node == node
  end

  test "execute_tick_with_context/2 uses context callback when available" do
    node = %ContextNode{}
    tick = Tick.new_with_context(Tick.new().blackboard, nil, [], %{})

    {status, updated_node, updated_tick} = Node.execute_tick_with_context(node, tick)

    assert status == :success
    assert updated_node.value == 1
    assert Tick.get(updated_tick, :context_node) == true
  end

  test "execute_tick_with_context/2 falls back to tick/2 for normal nodes" do
    node = SimpleNode.new("fallback")
    tick = Tick.new_with_context(Tick.new().blackboard, nil, [], %{})

    {status, updated_node, passthrough_tick} = Node.execute_tick_with_context(node, tick)

    assert status == :success
    assert updated_node.tick_count == 1
    assert passthrough_tick == tick
  end

  test "execute_halt/1 handles halt exceptions by returning original node" do
    node = %RaisingNode{}
    assert Node.execute_halt(node) == node
  end

  test "node?/1 validates node-like structs" do
    assert Node.node?(SimpleNode.new("node"))
    refute Node.node?("not-a-node")
  end
end
