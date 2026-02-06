defmodule JidoExampleTest.ParentChildTest do
  @moduledoc """
  Example test demonstrating parent-child request/response patterns.

  This test shows:
  - Parent (coordinator) spawning child (worker) agents via SpawnAgent directive
  - Handling jido.agent.child.started signals to initiate work
  - Child agents using emit_to_parent to send results back
  - Correlation ID tracking for request/response matching
  - Aggregating results from multiple workers

  ## Usage

  Run with: mix test --include example test/examples/parent_child_test.exs

  ## Key Patterns

  1. **Spawning Workers**: Coordinator emits `SpawnAgent` directive with a tag
  2. **Child Started**: Coordinator receives `jido.agent.child.started` and sends work
  3. **Work Processing**: Worker processes work and uses `emit_to_parent` to reply
  4. **Correlation**: Use request_id in signal data to match responses to requests
  5. **Aggregation**: Coordinator tracks pending requests and completed responses

  ## Architecture

      Coordinator                          Worker
          |                                   |
          |-- SpawnAgent(:worker_1) --------->|
          |                                   |
          |<-- jido.agent.child.started ------|
          |                                   |
          |-- work.request (request_id) ----->|
          |                                   |
          |                          [process work]
          |                                   |
          |<-- work.result (request_id) ------|
          |                                   |
     [aggregate result]                       |
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 25_000

  alias Jido.Agent.Directive
  alias Jido.Agent.StateOp
  alias Jido.AgentServer
  alias Jido.Signal

  # ===========================================================================
  # ACTIONS: Worker operations
  # ===========================================================================

  defmodule SpawnWorkerAction do
    @moduledoc false
    use Jido.Action,
      name: "spawn_worker",
      schema: [
        worker_tag: [type: :atom, required: true],
        work_data: [type: :map, default: %{}]
      ]

    def run(%{worker_tag: tag, work_data: work_data}, _context) do
      spawn_directive =
        Directive.spawn_agent(
          JidoExampleTest.ParentChildTest.WorkerAgent,
          tag,
          meta: %{work_data: work_data}
        )

      {:ok, %{}, [spawn_directive]}
    end
  end

  defmodule HandleChildStartedAction do
    @moduledoc false
    use Jido.Action,
      name: "handle_child_started",
      schema: [
        parent_id: [type: :string, required: true],
        child_id: [type: :string, required: true],
        child_module: [type: :any, required: true],
        tag: [type: :any, required: true],
        pid: [type: :any, required: true],
        meta: [type: :map, default: %{}]
      ]

    def run(%{pid: pid, tag: tag, meta: meta}, context) do
      work_data = Map.get(meta, :work_data, %{})
      request_id = "req-#{System.unique_integer([:positive])}"

      pending = Map.get(context.state, :pending_requests, %{})

      updated_pending =
        Map.put(pending, request_id, %{tag: tag, pid: pid, started_at: DateTime.utc_now()})

      work_signal =
        Signal.new!(
          "work.request",
          Map.merge(work_data, %{request_id: request_id}),
          source: "/coordinator"
        )

      emit_directive = Directive.emit_to_pid(work_signal, pid)

      {:ok, %{pending_requests: updated_pending}, [emit_directive]}
    end
  end

  defmodule ProcessWorkAction do
    @moduledoc false
    use Jido.Action,
      name: "process_work",
      schema: [
        request_id: [type: :string, required: true],
        value: [type: :integer, default: 0],
        operation: [type: :atom, default: :double]
      ]

    def run(%{request_id: request_id, value: value, operation: operation}, context) do
      result =
        case operation do
          :double -> value * 2
          :square -> value * value
          :increment -> value + 1
          _ -> value
        end

      result_signal =
        Signal.new!(
          "work.result",
          %{request_id: request_id, result: result, operation: operation},
          source: "/worker"
        )

      # Use %{state: context.state} to match emit_to_parent's expected pattern
      agent_like = %{state: context.state}
      emit_directive = Directive.emit_to_parent(agent_like, result_signal)

      {:ok, %{last_processed: %{request_id: request_id, result: result}},
       List.wrap(emit_directive)}
    end
  end

  defmodule HandleResultAction do
    @moduledoc false
    use Jido.Action,
      name: "handle_result",
      schema: [
        request_id: [type: :string, required: true],
        result: [type: :any, required: true],
        operation: [type: :atom, default: :unknown]
      ]

    def run(%{request_id: request_id, result: result, operation: operation}, context) do
      pending = Map.get(context.state, :pending_requests, %{})
      responses = Map.get(context.state, :completed_responses, [])

      {request_info, remaining_pending} = Map.pop(pending, request_id, nil)

      response_entry = %{
        request_id: request_id,
        result: result,
        operation: operation,
        worker_tag: request_info && request_info.tag,
        completed_at: DateTime.utc_now()
      }

      # Use SetPath to properly replace pending_requests (deep merge doesn't remove keys)
      set_pending_op = StateOp.set_path([:pending_requests], remaining_pending)

      {:ok, %{completed_responses: [response_entry | responses]}, [set_pending_op]}
    end
  end

  # ===========================================================================
  # AGENTS: Coordinator and Worker
  # ===========================================================================

  defmodule CoordinatorAgent do
    @moduledoc false
    use Jido.Agent,
      name: "coordinator_agent",
      schema: [
        pending_requests: [type: :map, default: %{}],
        completed_responses: [type: {:list, :map}, default: []],
        workers_spawned: [type: :integer, default: 0]
      ]

    def signal_routes(_ctx) do
      [
        {"spawn_worker", SpawnWorkerAction},
        {"jido.agent.child.started", HandleChildStartedAction},
        {"work.result", HandleResultAction}
      ]
    end
  end

  defmodule WorkerAgent do
    @moduledoc false
    use Jido.Agent,
      name: "worker_agent",
      schema: [
        last_processed: [type: :map, default: nil],
        status: [type: :atom, default: :idle]
      ]

    def signal_routes(_ctx) do
      [
        {"work.request", ProcessWorkAction}
      ]
    end
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "parent spawns worker" do
    test "coordinator spawns worker and worker starts", %{jido: jido} do
      {:ok, coordinator_pid} =
        Jido.start_agent(jido, CoordinatorAgent, id: unique_id("coordinator"))

      signal =
        Signal.new!(
          "spawn_worker",
          %{worker_tag: :worker_1, work_data: %{value: 5, operation: :double}},
          source: "/test"
        )

      {:ok, _agent} = AgentServer.call(coordinator_pid, signal)

      eventually(
        fn ->
          case AgentServer.state(coordinator_pid) do
            {:ok, %{children: children}} -> Map.has_key?(children, :worker_1)
            _ -> false
          end
        end,
        timeout: 5_000
      )

      {:ok, state} = AgentServer.state(coordinator_pid)
      assert Map.has_key?(state.children, :worker_1)
      assert is_pid(state.children[:worker_1].pid)
    end
  end

  describe "request/response with correlation" do
    test "parent sends work request with correlation ID, child responds", %{jido: jido} do
      {:ok, coordinator_pid} =
        Jido.start_agent(jido, CoordinatorAgent, id: unique_id("coordinator"))

      signal =
        Signal.new!(
          "spawn_worker",
          %{worker_tag: :math_worker, work_data: %{value: 7, operation: :double}},
          source: "/test"
        )

      {:ok, _agent} = AgentServer.call(coordinator_pid, signal)

      eventually(
        fn ->
          case AgentServer.state(coordinator_pid) do
            {:ok, %{agent: %{state: %{completed_responses: responses}}}} ->
              responses != []

            _ ->
              false
          end
        end,
        timeout: 10_000
      )

      {:ok, final_state} = AgentServer.state(coordinator_pid)
      [response | _] = final_state.agent.state.completed_responses

      assert response.result == 14
      assert response.operation == :double
      assert response.worker_tag == :math_worker
      assert response.request_id != nil
    end

    test "correlation IDs match between request and response", %{jido: jido} do
      {:ok, coordinator_pid} =
        Jido.start_agent(jido, CoordinatorAgent, id: unique_id("coordinator"))

      signal =
        Signal.new!(
          "spawn_worker",
          %{worker_tag: :square_worker, work_data: %{value: 4, operation: :square}},
          source: "/test"
        )

      {:ok, _agent} = AgentServer.call(coordinator_pid, signal)

      eventually(
        fn ->
          case AgentServer.state(coordinator_pid) do
            {:ok, %{agent: %{state: %{completed_responses: responses}}}} ->
              responses != []

            _ ->
              false
          end
        end,
        timeout: 10_000
      )

      {:ok, final_state} = AgentServer.state(coordinator_pid)

      [response | _] = final_state.agent.state.completed_responses
      assert response.result == 16
      assert response.request_id =~ ~r/^req-\d+$/

      # Verify that the pending request was cleared when the response was processed
      refute Map.has_key?(final_state.agent.state.pending_requests, response.request_id)
    end
  end

  describe "aggregating results from multiple workers" do
    test "parent aggregates results from multiple workers", %{jido: jido} do
      {:ok, coordinator_pid} =
        Jido.start_agent(jido, CoordinatorAgent, id: unique_id("coordinator"))

      work_configs = [
        {:worker_a, %{value: 2, operation: :double}},
        {:worker_b, %{value: 3, operation: :square}},
        {:worker_c, %{value: 10, operation: :increment}}
      ]

      for {tag, work_data} <- work_configs do
        signal =
          Signal.new!(
            "spawn_worker",
            %{worker_tag: tag, work_data: work_data},
            source: "/test"
          )

        {:ok, _} = AgentServer.call(coordinator_pid, signal)
      end

      eventually(
        fn ->
          case AgentServer.state(coordinator_pid) do
            {:ok, %{agent: %{state: %{completed_responses: responses}}}} ->
              match?([_, _, _ | _], responses)

            _ ->
              false
          end
        end,
        timeout: 15_000
      )

      {:ok, final_state} = AgentServer.state(coordinator_pid)
      responses = final_state.agent.state.completed_responses

      assert length(responses) == 3

      results_by_tag = Map.new(responses, fn r -> {r.worker_tag, r.result} end)

      assert results_by_tag[:worker_a] == 4
      assert results_by_tag[:worker_b] == 9
      assert results_by_tag[:worker_c] == 11

      # Verify all processed request_ids were cleared from pending
      processed_request_ids = Enum.map(responses, & &1.request_id)

      for req_id <- processed_request_ids do
        refute Map.has_key?(final_state.agent.state.pending_requests, req_id)
      end
    end

    test "each worker result has unique correlation ID", %{jido: jido} do
      {:ok, coordinator_pid} =
        Jido.start_agent(jido, CoordinatorAgent, id: unique_id("coordinator"))

      for i <- 1..3 do
        signal =
          Signal.new!(
            "spawn_worker",
            %{worker_tag: :"worker_#{i}", work_data: %{value: i, operation: :double}},
            source: "/test"
          )

        {:ok, _} = AgentServer.call(coordinator_pid, signal)
      end

      eventually(
        fn ->
          case AgentServer.state(coordinator_pid) do
            {:ok, %{agent: %{state: %{completed_responses: responses}}}} ->
              match?([_, _, _ | _], responses)

            _ ->
              false
          end
        end,
        timeout: 15_000
      )

      {:ok, final_state} = AgentServer.state(coordinator_pid)
      responses = final_state.agent.state.completed_responses

      request_ids = Enum.map(responses, & &1.request_id)
      assert length(Enum.uniq(request_ids)) == 3
    end
  end

  describe "emit_to_parent patterns" do
    test "worker without parent returns nil for emit_to_parent", %{jido: jido} do
      {:ok, orphan_pid} = Jido.start_agent(jido, WorkerAgent, id: unique_id("orphan"))

      signal =
        Signal.new!(
          "work.request",
          %{request_id: "orphan-req", value: 5, operation: :double},
          source: "/test"
        )

      {:ok, agent} = AgentServer.call(orphan_pid, signal)

      assert agent.state.last_processed.result == 10
      assert agent.state.last_processed.request_id == "orphan-req"
    end

    test "child with parent successfully emits to parent", %{jido: jido} do
      {:ok, coordinator_pid} =
        Jido.start_agent(jido, CoordinatorAgent, id: unique_id("coordinator"))

      signal =
        Signal.new!(
          "spawn_worker",
          %{worker_tag: :emit_test_worker, work_data: %{value: 100, operation: :increment}},
          source: "/test"
        )

      {:ok, _agent} = AgentServer.call(coordinator_pid, signal)

      eventually(
        fn ->
          case AgentServer.state(coordinator_pid) do
            {:ok, %{agent: %{state: %{completed_responses: responses}}}} ->
              Enum.any?(responses, fn r -> r.result == 101 end)

            _ ->
              false
          end
        end,
        timeout: 10_000
      )

      {:ok, final_state} = AgentServer.state(coordinator_pid)
      [response | _] = final_state.agent.state.completed_responses

      assert response.result == 101
      assert response.worker_tag == :emit_test_worker
    end
  end
end
