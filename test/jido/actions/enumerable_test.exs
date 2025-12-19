defmodule JidoTest.Actions.EnumerableTest do
  use ExUnit.Case

  alias Jido.Actions.Enumerable
  alias Jido.Agent.Directive.Enqueue

  describe "run/2" do
    test "processes first item with more remaining" do
      params = %{
        action: SomeAction,
        items: ["a", "b", "c"],
        params: %{type: "process"},
        item_key: :data,
        index_key: :position,
        current_index: 0
      }

      assert {:ok, result, [target_directive, next_directive]} = Enumerable.run(params, %{})

      assert result.index == 0
      assert result.total == 3
      assert result.action == SomeAction
      assert result.item == "a"
      assert result.final == false

      assert %Enqueue{
               action: SomeAction,
               params: %{type: "process", data: "a", position: 0}
             } = target_directive

      assert %Enqueue{
               action: Enumerable,
               params: %{
                 action: SomeAction,
                 items: ["a", "b", "c"],
                 params: %{type: "process"},
                 item_key: :data,
                 index_key: :position,
                 current_index: 1
               }
             } = next_directive
    end

    test "processes final item" do
      params = %{
        action: SomeAction,
        items: ["x", "y"],
        params: %{mode: "final"},
        item_key: :item,
        index_key: :index,
        current_index: 1
      }

      assert {:ok, result, [target_directive]} = Enumerable.run(params, %{})

      assert result.index == 1
      assert result.total == 2
      assert result.action == SomeAction
      assert result.item == "y"
      assert result.final == true

      assert %Enqueue{
               action: SomeAction,
               params: %{mode: "final", item: "y", index: 1}
             } = target_directive
    end

    test "processes single item" do
      params = %{
        action: SomeAction,
        items: [42],
        params: %{operation: "single"},
        item_key: :value,
        index_key: :pos,
        current_index: 0
      }

      assert {:ok, result, [target_directive]} = Enumerable.run(params, %{})

      assert result.index == 0
      assert result.total == 1
      assert result.final == true

      assert %Enqueue{
               action: SomeAction,
               params: %{operation: "single", value: 42, pos: 0}
             } = target_directive
    end

    test "uses default keys when not specified" do
      params = %{
        action: SomeAction,
        items: ["test"],
        params: %{base: "param"},
        current_index: 0
      }

      assert {:ok, result, [target_directive]} = Enumerable.run(params, %{})

      assert result.item == "test"
      assert result.final == true

      assert %Enqueue{
               action: SomeAction,
               params: %{base: "param", item: "test", index: 0}
             } = target_directive
    end

    test "handles empty base params" do
      params = %{
        action: SomeAction,
        items: [1, 2],
        params: %{},
        current_index: 0
      }

      assert {:ok, result, [target_directive, _next_directive]} = Enumerable.run(params, %{})

      assert result.item == 1
      assert result.final == false

      assert %Enqueue{
               action: SomeAction,
               params: %{item: 1, index: 0}
             } = target_directive
    end

    test "returns error when current_index exceeds items length" do
      params = %{
        action: SomeAction,
        items: ["a", "b"],
        current_index: 3
      }

      assert {:error, "Current index (3) exceeds items length (2)"} = Enumerable.run(params, %{})
    end

    test "processes different data types" do
      params = %{
        action: SomeAction,
        items: [%{id: 1}, %{id: 2}],
        params: %{action_type: "map_process"},
        current_index: 0
      }

      assert {:ok, result, [target_directive, _next_directive]} = Enumerable.run(params, %{})

      assert result.item == %{id: 1}

      assert %Enqueue{
               action: SomeAction,
               params: %{action_type: "map_process", item: %{id: 1}, index: 0}
             } = target_directive
    end

    test "validates items list is not empty" do
      assert {:error, "Items list cannot be empty"} = Enumerable.run(%{items: []}, %{})
    end

    test "validates schema includes required fields" do
      schema = Enumerable.schema()
      items_schema = Keyword.get(schema, :items, [])
      assert Keyword.get(items_schema, :required) == true
      assert Keyword.get(items_schema, :type) == {:list, :any}
    end
  end
end
