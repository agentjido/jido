defmodule Jido.Signal.RouterTest do
  use ExUnit.Case, async: true

  alias Jido.Instruction
  alias Jido.Signal
  alias Jido.Signal.Router
  alias JidoTest.TestActions.{Add, Multiply, Subtract, FormatUser, EnrichUserData}
  @moduletag :capture_log

  setup do
    routes = [
      # Static route - adds 1 to value
      {"user.created", %Instruction{action: Add}},

      # Single wildcard route - multiplies value by 2
      {"user.*.updated", %Instruction{action: Multiply}},

      # Multi-level wildcard route - subtracts 1 from value
      {"order.**.completed", %Instruction{action: Subtract}},

      # Priority route - formats user data
      {"user.format", %Instruction{action: FormatUser}, 100},

      # Pattern match route - enriches user data if email present
      {
        "user.enrich",
        fn signal -> Map.has_key?(signal.data, :email) end,
        %Instruction{action: EnrichUserData},
        90
      }
    ]

    {:ok, router} = Router.new(routes)
    {:ok, %{router: router}}
  end

  describe "route/2" do
    test "routes static path signal", %{router: router} do
      signal = %Signal{
        id: UUID.uuid4(),
        source: "/test",
        type: "user.created",
        data: %{value: 5}
      }

      assert {:ok, [%Instruction{action: Add}]} = Router.route(router, signal)
    end

    test "routes single wildcard signal", %{router: router} do
      signal = %Signal{
        id: UUID.uuid4(),
        source: "/test",
        type: "user.123.updated",
        data: %{value: 10}
      }

      assert {:ok, [%Instruction{action: Multiply}]} = Router.route(router, signal)
    end

    test "routes multi-level wildcard signal", %{router: router} do
      signal = %Signal{
        id: UUID.uuid4(),
        source: "/test",
        type: "order.123.payment.completed",
        data: %{value: 20}
      }

      assert {:ok, [%Instruction{action: Subtract}]} = Router.route(router, signal)
    end

    test "routes by priority", %{router: router} do
      signal = %Signal{
        id: UUID.uuid4(),
        source: "/test",
        type: "user.format",
        data: %{
          name: "John Doe",
          email: "john@example.com",
          age: 30
        }
      }

      assert {:ok, [%Instruction{action: FormatUser}]} = Router.route(router, signal)
    end

    test "routes pattern matched signal", %{router: router} do
      signal = %Signal{
        id: UUID.uuid4(),
        source: "/test",
        type: "user.enrich",
        data: %{
          formatted_name: "John Doe",
          email: "john@example.com"
        }
      }

      assert {:ok, [%Instruction{action: EnrichUserData}]} = Router.route(router, signal)
    end

    test "does not route pattern matched signal when condition fails", %{router: router} do
      signal = %Signal{
        id: UUID.uuid4(),
        source: "/test",
        type: "user.enrich",
        data: %{
          formatted_name: "John Doe"
          # Missing email field
        }
      }

      assert {:error, error} = Router.route(router, signal)
      assert error.type == :routing_error
      assert error.message == :no_handler
    end

    test "returns empty list for unmatched path", %{router: router} do
      signal = %Signal{
        id: UUID.uuid4(),
        source: "/test",
        type: "unknown.path",
        data: %{}
      }

      assert {:error, error} = Router.route(router, signal)
      assert error.type == :routing_error
      assert error.message == :no_handler
    end
  end

  describe "router edge cases" do
    test "handles path pattern edge cases", %{router: _router} do
      # Test empty path segments
      {:error, error} = Router.new({"user..created", %Instruction{action: TestAction}})
      assert error.type == :routing_error

      # Test paths ending in wildcard
      {:ok, router} = Router.new({"user.*", %Instruction{action: TestAction}})
      signal = %Signal{type: "user.anything", source: "/test", id: UUID.uuid4()}
      {:ok, [instruction]} = Router.route(router, signal)
      assert instruction.action == TestAction

      # Test paths starting with wildcard
      {:ok, router} = Router.new({"*.created", %Instruction{action: TestAction}})
      signal = %Signal{type: "anything.created", source: "/test", id: UUID.uuid4()}
      {:ok, [instruction]} = Router.route(router, signal)
      assert instruction.action == TestAction

      # Test multiple consecutive wildcards
      {:error, error} = Router.new({"user.**.**.created", %Instruction{action: TestAction}})
      assert error.type == :routing_error
      assert error.message == :invalid_path_format
    end

    test "handles priority edge cases", %{router: _router} do
      # Test priority bounds
      {:error, error} =
        Router.new({
          "test",
          %Instruction{action: TestAction},
          # Above max
          101
        })

      assert error.type == :routing_error

      {:error, error} =
        Router.new({
          "test",
          %Instruction{action: TestAction},
          # Below min
          -101
        })

      assert error.type == :routing_error

      # Test same priority ordering
      {:ok, router} =
        Router.new([
          {"test", %Instruction{action: Action1}, 0},
          {"test", %Instruction{action: Action2}, 0}
        ])

      signal = %Signal{type: "test", source: "/test", id: UUID.uuid4()}
      {:ok, instructions} = Router.route(router, signal)
      # Should maintain registration order
      assert [%Instruction{action: Action1}, %Instruction{action: Action2}] = instructions
    end

    test "handles pattern matching edge cases" do
      # Test pattern function that raises
      {:error, error} =
        Router.new({
          "test",
          fn _signal -> raise "boom" end,
          %Instruction{action: TestAction}
        })

      assert error.type == :routing_error

      # Test pattern function returning non-boolean
      pattern_fn = fn _signal -> "not a boolean" end

      {:error, error} =
        Router.new({
          "test",
          pattern_fn,
          %Instruction{action: TestAction}
        })

      assert error.type == :routing_error

      # Test pattern function with nil signal data
      {:ok, router} =
        Router.new({
          "test",
          fn signal -> Map.get(signal.data, :key) == "value" end,
          %Instruction{action: TestAction}
        })

      signal = %Signal{type: "test", source: "/test", id: UUID.uuid4(), data: nil}
      {:error, error} = Router.route(router, signal)
      assert error.type == :routing_error
    end

    test "handles route management edge cases" do
      # Test adding duplicate routes
      {:ok, router} = Router.new({"test", %Instruction{action: Action1}})
      {:ok, router} = Router.add(router, {"test", %Instruction{action: Action2}})
      signal = %Signal{type: "test", source: "/test", id: UUID.uuid4()}
      {:ok, instructions} = Router.route(router, signal)
      # Should have both instructions
      assert length(instructions) == 2

      # Test removing non-existent route
      {:ok, router} = Router.remove(router, "nonexistent")
      # Should not error

      # Test removing last route
      {:ok, router} = Router.remove(router, "test")
      signal = %Signal{type: "test", source: "/test", id: UUID.uuid4()}
      {:error, error} = Router.route(router, signal)
      assert error.type == :routing_error
      assert error.message == :no_handler
    end

    test "handles signal type edge cases", %{router: router} do
      # Test empty signal type
      signal = %Signal{type: "", source: "/test", id: UUID.uuid4()}
      {:error, error} = Router.route(router, signal)
      assert error.type == :routing_error

      # Test very long path
      long_type = String.duplicate("a.", 100) <> "end"
      signal = %Signal{type: long_type, source: "/test", id: UUID.uuid4()}
      {:error, error} = Router.route(router, signal)
      assert error.type == :routing_error

      # Test invalid characters in type
      signal = %Signal{type: "user@123", source: "/test", id: UUID.uuid4()}
      {:error, error} = Router.route(router, signal)
      assert error.type == :routing_error
    end

    test "handles complex wildcard interactions" do
      {:ok, router} =
        Router.new([
          {"**", %Instruction{action: CatchAll}, -100},
          {"*.*.created", %Instruction{action: Action1}},
          {"user.**", %Instruction{action: Action2}},
          {"user.*.created", %Instruction{action: Action3}},
          {"user.123.created", %Instruction{action: Action4}}
        ])

      # Test overlapping wildcards
      signal = %Signal{type: "user.123.created", source: "/test", id: UUID.uuid4()}
      {:ok, instructions} = Router.route(router, signal)
      # Should match all patterns in correct priority order
      assert [
               %{action: Action4},
               %{action: Action3},
               %{action: Action2},
               %{action: Action1},
               %{action: CatchAll}
             ] = instructions
    end

    test "handles trie node edge cases" do
      # Test very deep nesting - over 10 and the tests are really slow
      deep_path = String.duplicate("nested.", 10) <> "end"

      {:ok, router} =
        Router.new({
          deep_path,
          %Instruction{action: TestAction}
        })

      signal = %Signal{type: deep_path, source: "/test", id: UUID.uuid4()}
      {:ok, [instruction]} = Router.route(router, signal)
      assert instruction.action == TestAction

      # Test wide trie (many siblings)
      wide_routes =
        for n <- 1..1000 do
          {"parent.#{n}", %Instruction{action: TestAction}}
        end

      {:ok, router} = Router.new(wide_routes)

      signal = %Signal{type: "parent.500", source: "/test", id: UUID.uuid4()}
      {:ok, [instruction]} = Router.route(router, signal)
      assert instruction.action == TestAction
    end
  end
end
