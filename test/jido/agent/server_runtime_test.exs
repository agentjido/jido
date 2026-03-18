defmodule JidoTest.Agent.ServerRuntimeTest do
  use JidoTest.Case, async: true
  require Logger

  alias Jido.Agent.Server.State, as: ServerState
  alias JidoTest.TestActions.NoSchema
  alias JidoTest.TestAgents.BasicAgent

  alias Jido.Agent.Server.Runtime, as: ServerRuntime
  alias Jido.Agent.Server.Router, as: ServerRouter
  alias Jido.{Error, Signal, Instruction}

  @moduletag :capture_log

  describe "extract_opts_from_first_instruction/1" do
    test "extracts opts from first instruction" do
      {:ok, instruction} = Instruction.new(%{action: NoSchema, opts: [foo: "bar"]})

      assert {:ok, [foo: "bar"]} =
               ServerRuntime.extract_opts_from_first_instruction([instruction])
    end

    test "returns empty list for empty instructions" do
      assert {:ok, []} = ServerRuntime.extract_opts_from_first_instruction([])
    end

    test "returns empty list when first instruction has no opts" do
      {:ok, instruction} = Instruction.new(%{action: NoSchema, opts: nil})
      assert {:ok, []} = ServerRuntime.extract_opts_from_first_instruction([instruction])
    end
  end

  describe "route_signal/2" do
    test "returns error when no routes match" do
      state = %ServerState{agent: BasicAgent.new("test")}
      signal = Signal.new!(%{type: "nonexistent", id: "test-id-123"})

      assert {:error, %Jido.Signal.Error.RoutingError{}} =
               ServerRuntime.route_signal(state, signal)
    end

    test "routes signal successfully" do
      {:ok, instruction} = Instruction.new(%{action: NoSchema})
      base_state = %ServerState{agent: BasicAgent.new("test")}
      {:ok, router_state} = ServerRouter.build(base_state, routes: [{"test", instruction}])
      state = %{base_state | router: router_state.router}
      signal = Signal.new!(%{type: "test", id: "test-id-456"})

      assert {:ok, [%Instruction{}]} = ServerRuntime.route_signal(state, signal)
    end

    test "returns error for invalid signal" do
      base_state = %ServerState{agent: BasicAgent.new("test")}
      {:ok, instruction} = Instruction.new(%{action: NoSchema})
      {:ok, router_state} = ServerRouter.build(base_state, routes: [{"test", instruction}])
      state = %{base_state | router: router_state.router}

      assert {:error, :invalid_signal} = ServerRuntime.route_signal(state, :invalid)
    end

    @tag :flaky
    test "returns error for non-matching route" do
      {:ok, instruction} = Instruction.new(%{action: NoSchema})
      base_state = %ServerState{agent: BasicAgent.new("test")}
      {:ok, router_state} = ServerRouter.build(base_state, routes: [{"test", instruction}])
      signal = Signal.new!(%{type: "non_existent", id: "test-id-789"})
      state = %{base_state | router: router_state.router, current_signal: signal}

      assert {:error, error} = ServerRuntime.route_signal(state, signal)
      # Verify it's a routing error - could be either an atom or an error struct
      assert (is_atom(error) and error == :no_matching_route) or
               (Exception.exception?(error) and Error.to_map(error).type == :routing_error)
    end
  end

  describe "process_signal/2" do
    setup do
      agent = BasicAgent.new("test")

      state = %ServerState{
        agent: agent,
        dispatch: [pid: [target: self()]]
      }

      # Build router with test routes
      {:ok, instruction} =
        Instruction.new(%{
          action: JidoTest.TestActions.BasicAction,
          params: %{value: 42}
        })

      {:ok, state} =
        ServerRouter.build(state,
          routes: [
            {"test.basic", instruction}
          ]
        )

      {:ok, state: state}
    end

    test "processes synchronous signal with reply ref", %{state: state} do
      signal = %Signal{
        type: "test.basic",
        source: "test",
        id: "test-1",
        data: %{value: 42}
      }

      from = {self(), make_ref()}

      # Store reply ref and process signal
      state = ServerState.store_reply_ref(state, signal.id, from)
      {:ok, new_state, result} = ServerRuntime.process_signal(state, signal)

      # Verify reply ref was removed
      assert ServerState.get_reply_ref(new_state, signal.id) == nil
      assert result.value == 42
    end

    test "processes asynchronous signal without reply ref", %{state: state} do
      signal = %Signal{
        type: "test.basic",
        source: "test",
        id: "test-2",
        data: %{value: 42}
      }

      {:ok, new_state, result} = ServerRuntime.process_signal(state, signal)

      # Verify state and result
      assert new_state != nil
      assert result.value == 42
    end
  end
end
