defmodule JidoTest.Actions.IteratorTest do
  use ExUnit.Case

  alias Jido.Actions.Iterator
  alias Jido.Agent.Directive.Enqueue

  describe "run/2" do
    test "executes first iteration with more remaining" do
      params = %{
        action: SomeAction,
        count: 3,
        params: %{value: 10},
        index: 1
      }

      assert {:ok, result, [target_directive, next_directive]} = Iterator.run(params, %{})

      assert result.index == 1
      assert result.count == 3
      assert result.action == SomeAction
      assert result.params == %{value: 10}
      assert result.final == false

      assert %Enqueue{action: SomeAction, params: %{value: 10}} = target_directive

      assert %Enqueue{
               action: Iterator,
               params: %{
                 action: SomeAction,
                 count: 3,
                 params: %{value: 10},
                 index: 2
               }
             } = next_directive
    end

    test "executes final iteration" do
      params = %{
        action: SomeAction,
        count: 3,
        params: %{value: 10},
        index: 3
      }

      assert {:ok, result, [target_directive]} = Iterator.run(params, %{})

      assert result.index == 3
      assert result.count == 3
      assert result.action == SomeAction
      assert result.params == %{value: 10}
      assert result.final == true

      assert %Enqueue{action: SomeAction, params: %{value: 10}} = target_directive
    end

    test "executes single iteration" do
      params = %{
        action: SomeAction,
        count: 1,
        params: %{value: 10},
        index: 1
      }

      assert {:ok, result, [target_directive]} = Iterator.run(params, %{})

      assert result.index == 1
      assert result.count == 1
      assert result.final == true

      assert %Enqueue{action: SomeAction, params: %{value: 10}} = target_directive
    end

    test "handles empty params" do
      params = %{
        action: SomeAction,
        count: 2,
        params: %{},
        index: 1
      }

      assert {:ok, result, [target_directive, _next_directive]} = Iterator.run(params, %{})

      assert result.params == %{}
      assert result.final == false
      assert %Enqueue{action: SomeAction, params: %{}} = target_directive
    end

    test "validates count is positive" do
      assert {:error, "Count must be positive"} = Iterator.run(%{count: 0}, %{})
      assert {:error, "Count must be positive"} = Iterator.run(%{count: -1}, %{})
    end

    test "validates schema includes required fields" do
      schema = Iterator.schema()
      count_schema = Keyword.get(schema, :count, [])
      assert Keyword.get(count_schema, :required) == true
      assert Keyword.get(count_schema, :type) == :pos_integer
    end

    test "works with large count" do
      params = %{
        action: SomeAction,
        count: 1000,
        params: %{value: 1},
        index: 500
      }

      assert {:ok, result, [_target_directive, next_directive]} = Iterator.run(params, %{})

      assert result.index == 500
      assert result.count == 1000
      assert result.final == false

      assert %Enqueue{
               params: %{
                 index: 501
               }
             } = next_directive
    end
  end
end
