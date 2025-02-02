defmodule Jido.Agent.Server.RouterTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Server.Router
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Signal
  alias Jido.Signal.Router.Route
  alias Jido.Instruction

  setup do
    state = %ServerState{
      router: Signal.Router.new!(),
      agent: nil,
      output: nil,
      status: :idle,
      pending_signals: [],
      max_queue_size: 1000
    }

    {:ok, state: state}
  end

  describe "build/2" do
    test "builds router with empty routes", %{state: state} do
      assert {:ok, updated_state} = Router.build(state, [])
      assert updated_state.router != nil
    end

    test "builds router with valid routes", %{state: state} do
      routes = [
        {"test.signal", %Instruction{action: :test_action}},
        {"another.signal", %Instruction{action: :another_action}}
      ]

      assert {:ok, updated_state} = Router.build(state, routes: routes)
      {:ok, {:ok, routes_list}} = Router.list(updated_state)
      assert length(routes_list) == 2
      assert Enum.any?(routes_list, fn route -> route.path == "test.signal" end)
      assert Enum.any?(routes_list, fn route -> route.path == "another.signal" end)
    end

    test "returns error for invalid routes", %{state: state} do
      assert {:error, error} = Router.build(state, routes: :invalid)
      assert error.type == :validation_error
      assert error.message == "Routes must be a list"

      # This error comes directly from Signal.Router
      assert {:error, error} = Router.build(state, routes: [{"test", :not_an_instruction}])
      assert error.type == :validation_error
      assert error.message == "Invalid route specification format"

      assert error.details.expected_formats == [
               "%Route{}",
               "{path, instruction}",
               "{path, instruction, priority}",
               "{path, match_fn, instruction}",
               "{path, match_fn, instruction, priority}"
             ]
    end
  end

  describe "add/2" do
    test "adds single route", %{state: state} do
      route = {"test.signal", %Instruction{action: :test_action}}
      assert {:ok, updated_state} = Router.add(state, route)
      {:ok, {:ok, routes}} = Router.list(updated_state)
      assert length(routes) == 1
      assert hd(routes).path == "test.signal"
    end

    test "adds multiple routes", %{state: state} do
      routes = [
        {"test.signal", %Instruction{action: :test_action}},
        {"another.signal", %Instruction{action: :another_action}}
      ]

      assert {:ok, updated_state} = Router.add(state, routes)
      {:ok, {:ok, routes_list}} = Router.list(updated_state)
      assert length(routes_list) == 2
    end
  end

  describe "remove/2" do
    setup %{state: state} do
      routes = [
        {"test.signal", %Instruction{action: :test_action}},
        {"another.signal", %Instruction{action: :another_action}}
      ]

      {:ok, state_with_routes} = Router.add(state, routes)
      {:ok, state: state_with_routes}
    end

    test "removes single route", %{state: state} do
      assert {:ok, updated_state} = Router.remove(state, "test.signal")
      {:ok, {:ok, routes}} = Router.list(updated_state)
      assert length(routes) == 1
      assert hd(routes).path == "another.signal"
    end

    test "removes multiple routes", %{state: state} do
      assert {:ok, updated_state} = Router.remove(state, ["test.signal", "another.signal"])
      {:ok, {:ok, routes}} = Router.list(updated_state)
      assert Enum.empty?(routes)
    end
  end

  describe "merge/2" do
    test "merges list of routes", %{state: state} do
      routes = [
        %Route{path: "test.path", instruction: %Instruction{action: :test_action}, priority: 0}
      ]

      assert {:ok, updated_state} = Router.merge(state, routes)
      {:ok, {:ok, merged_routes}} = Router.list(updated_state)
      assert length(merged_routes) == 1
    end

    test "merges another router", %{state: state} do
      other_router = Signal.Router.new!()

      {:ok, other_router} =
        Signal.Router.add(other_router, {"test.path", %Instruction{action: :test_action}})

      assert {:ok, updated_state} = Router.merge(state, other_router)
      {:ok, {:ok, merged_routes}} = Router.list(updated_state)
      assert length(merged_routes) == 1
    end

    test "returns error for invalid merge input", %{state: state} do
      assert {:error, error} = Router.merge(state, :invalid)
      assert error.type == :validation_error
    end
  end

  describe "route/2" do
    setup %{state: state} do
      route = {"test.signal", %Instruction{action: :test_action}}
      {:ok, state_with_route} = Router.add(state, route)
      {:ok, state: state_with_route}
    end

    test "routes signal to matching instruction", %{state: state} do
      {:ok, signal} = Signal.new(%{type: "test.signal", data: "test"})
      assert {:ok, [instruction]} = Router.route(state, signal)
      assert instruction.action == :test_action
    end

    test "returns error for non-matching signal", %{state: state} do
      {:ok, signal} = Signal.new(%{type: "nonexistent.signal", data: "test"})
      assert {:error, error} = Router.route(state, signal)
      assert error.type == :routing_error
      assert error.message == :no_handler
    end

    test "returns error for invalid signal", %{state: state} do
      assert {:error, error} = Router.route(state, :invalid)
      assert error.type == :validation_error
    end

    test "uses jido_instruction from signal if present", %{state: state} do
      direct_instruction = %Instruction{action: :direct_action}

      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          jido_instructions: [direct_instruction],
          data: %{}
        })

      assert {:ok, [instruction]} = Router.route(state, signal)
      assert instruction == direct_instruction
    end

    test "handles list of jido_instructions", %{state: state} do
      instructions = [
        %Instruction{action: :first_action},
        %Instruction{action: :second_action}
      ]

      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          data: %{},
          jido_instructions: instructions
        })

      assert {:ok, received_instructions} = Router.route(state, signal)
      assert length(received_instructions) == 2
      assert Enum.at(received_instructions, 0).action == :first_action
      assert Enum.at(received_instructions, 1).action == :second_action
    end

    test "falls back to router when no jido_instruction present", %{state: state} do
      route_instruction = %Instruction{action: :route_action}
      {:ok, state} = Router.add(state, {"special.signal", route_instruction})

      {:ok, signal} =
        Signal.new(%{
          type: "special.signal",
          data: %{some: "data"}
        })

      assert {:ok, [instruction]} = Router.route(state, signal)
      assert instruction == route_instruction
    end
  end
end
