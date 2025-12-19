defmodule JidoTest.Actions.WhileTest do
  use ExUnit.Case

  alias Jido.Actions.While
  alias Jido.Agent.Directive.Enqueue

  describe "run/2" do
    test "continues when condition is truthy" do
      params = %{
        body: SomeAction,
        params: %{continue: true, data: "test"},
        condition_field: :continue,
        max_iterations: 10,
        iteration: 1
      }

      assert {:ok, result, [body_directive, next_while_directive]} = While.run(params, %{})

      assert result.iteration == 1
      assert result.body == SomeAction
      assert result.condition_field == :continue
      assert result.continue == true
      refute Map.has_key?(result, :final)

      assert %Enqueue{action: SomeAction, params: %{continue: true, data: "test"}} =
               body_directive

      assert %Enqueue{
               action: While,
               params: %{
                 body: SomeAction,
                 params: %{continue: true, data: "test"},
                 condition_field: :continue,
                 max_iterations: 10,
                 iteration: 2
               }
             } = next_while_directive
    end

    test "exits when condition is falsy" do
      params = %{
        body: SomeAction,
        params: %{continue: false, data: "test"},
        condition_field: :continue,
        max_iterations: 10,
        iteration: 5
      }

      assert {:ok, result} = While.run(params, %{})

      assert result.iteration == 5
      assert result.body == SomeAction
      assert result.condition_field == :continue
      assert result.continue == false
      assert result.final == true
    end

    test "exits when condition field is missing" do
      params = %{
        body: SomeAction,
        params: %{data: "test"},
        condition_field: :continue,
        max_iterations: 10,
        iteration: 1
      }

      assert {:ok, result} = While.run(params, %{})

      assert result.continue == false
      assert result.final == true
    end

    test "returns error when max iterations exceeded" do
      params = %{
        iteration: 11,
        max_iterations: 10
      }

      assert {:error, "Maximum iterations (10) exceeded"} = While.run(params, %{})
    end

    test "works with custom condition field" do
      params = %{
        body: SomeAction,
        params: %{active: true, data: "test"},
        condition_field: :active,
        max_iterations: 10,
        iteration: 1
      }

      assert {:ok, result, [_body_directive, _next_while_directive]} = While.run(params, %{})

      assert result.condition_field == :active
      assert result.continue == true
    end

    test "handles nil condition value" do
      params = %{
        body: SomeAction,
        params: %{continue: nil, data: "test"},
        condition_field: :continue,
        max_iterations: 10,
        iteration: 1
      }

      assert {:ok, result} = While.run(params, %{})

      assert result.continue == false
      assert result.final == true
    end
  end
end
