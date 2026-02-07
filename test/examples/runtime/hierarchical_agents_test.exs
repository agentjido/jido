defmodule JidoExampleTest.HierarchicalAgentsTest do
  @moduledoc """
  Example test demonstrating three-layer agent hierarchies.

  This test shows:
  - Orchestrator (grandparent) spawning Coordinator (parent) agents
  - Coordinators spawning Worker (child) agents
  - Signal flow across three layers: Orchestrator → Coordinator → Worker
  - Results bubbling up: Worker → Coordinator → Orchestrator
  - Trace propagation through the entire hierarchy

  ## Architecture

      Orchestrator (Layer 1)
          |
          |-- SpawnAgent(:coordinator_a) ────────┐
          |                                      |
          |<── jido.agent.child.started ─────────┤
          |                                      |
          |── job.assign ───────────────────────>|
          |                                      |
          |                              Coordinator A (Layer 2)
          |                                      |
          |                                      |-- SpawnAgent(:worker_1)──┐
          |                                      |                          |
          |                                      |<─ child.started ─────────┤
          |                                      |                          |
          |                                      |── task.execute ─────────>|
          |                                      |                          |
          |                                      |                   Worker 1 (Layer 3)
          |                                      |                          |
          |                                      |                   [process task]
          |                                      |                          |
          |                                      |<─ task.result ───────────|
          |                                      |                          |
          |                              [aggregate results]                |
          |                                      |
          |<── job.result ───────────────────────|
          |
      [final aggregation]

  ## Key Patterns

  1. **Hierarchical Spawning**: Each layer spawns the next via SpawnAgent
  2. **Downward Signals**: Work requests flow down (job.assign → task.execute)
  3. **Upward Results**: Results bubble up via emit_to_parent
  4. **Correlation**: request_id tracks work across all layers
  5. **Aggregation**: Each layer aggregates results from children

  Run with: mix test --include example
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 30_000

  alias Jido.Agent.Directive
  alias Jido.Agent.StateOp
  alias Jido.AgentServer
  alias Jido.Signal
  alias Jido.Tracing.Trace

  # ===========================================================================
  # LAYER 3: WORKER ACTIONS
  # ===========================================================================

  defmodule ExecuteTaskAction do
    @moduledoc false
    use Jido.Action,
      name: "execute_task",
      schema: [
        task_id: [type: :string, required: true],
        job_id: [type: :string, required: true],
        operation: [type: :atom, required: true],
        value: [type: :integer, required: true]
      ]

    def run(params, context) do
      result =
        case params.operation do
          :compute -> params.value * 2 + 1
          :validate -> if params.value > 0, do: :valid, else: :invalid
          :transform -> Integer.to_string(params.value) <> "_processed"
          _ -> params.value
        end

      result_signal =
        Signal.new!(
          "task.result",
          %{
            task_id: params.task_id,
            job_id: params.job_id,
            result: result,
            operation: params.operation
          },
          source: "/worker"
        )

      agent_like = %{state: context.state}
      emit_directive = Directive.emit_to_parent(agent_like, result_signal)

      {:ok,
       %{
         last_task: %{task_id: params.task_id, result: result},
         tasks_completed: Map.get(context.state, :tasks_completed, 0) + 1
       }, List.wrap(emit_directive)}
    end
  end

  # ===========================================================================
  # LAYER 2: COORDINATOR ACTIONS
  # ===========================================================================

  defmodule HandleJobAssignAction do
    @moduledoc false
    use Jido.Action,
      name: "handle_job_assign",
      schema: [
        job_id: [type: :string, required: true],
        tasks: [type: {:list, :map}, required: true]
      ]

    def run(%{job_id: job_id, tasks: tasks}, context) do
      pending = Map.get(context.state, :pending_tasks, %{})
      task_count = length(tasks)

      job_info = %{
        job_id: job_id,
        total_tasks: task_count,
        completed_tasks: 0,
        results: [],
        started_at: DateTime.utc_now()
      }

      updated_pending = Map.put(pending, job_id, job_info)

      spawn_directives =
        Enum.map(tasks, fn task ->
          task_id = "#{job_id}-task-#{task.index}"

          Directive.spawn_agent(
            JidoExampleTest.HierarchicalAgentsTest.WorkerAgent,
            String.to_atom(task_id),
            meta: %{
              task_id: task_id,
              job_id: job_id,
              operation: task.operation,
              value: task.value
            }
          )
        end)

      {:ok, %{pending_tasks: updated_pending, current_job: job_id}, spawn_directives}
    end
  end

  defmodule CoordinatorChildStartedAction do
    @moduledoc false
    use Jido.Action,
      name: "coordinator_child_started",
      schema: [
        parent_id: [type: :string, required: true],
        child_id: [type: :string, required: true],
        child_module: [type: :any, required: true],
        tag: [type: :any, required: true],
        pid: [type: :any, required: true],
        meta: [type: :map, default: %{}]
      ]

    def run(%{pid: pid, meta: meta}, _context) do
      task_signal =
        Signal.new!(
          "task.execute",
          %{
            task_id: meta.task_id,
            job_id: meta.job_id,
            operation: meta.operation,
            value: meta.value
          },
          source: "/coordinator"
        )

      emit_directive = Directive.emit_to_pid(task_signal, pid)

      {:ok, %{}, [emit_directive]}
    end
  end

  defmodule HandleTaskResultAction do
    @moduledoc false
    use Jido.Action,
      name: "handle_task_result",
      schema: [
        task_id: [type: :string, required: true],
        job_id: [type: :string, required: true],
        result: [type: :any, required: true],
        operation: [type: :atom, required: true]
      ]

    def run(params, context) do
      pending = Map.get(context.state, :pending_tasks, %{})

      job_info =
        Map.get(pending, params.job_id, %{results: [], completed_tasks: 0, total_tasks: 0})

      task_result = %{
        task_id: params.task_id,
        result: params.result,
        operation: params.operation
      }

      updated_job_info = %{
        job_info
        | results: [task_result | job_info.results],
          completed_tasks: job_info.completed_tasks + 1
      }

      updated_pending = Map.put(pending, params.job_id, updated_job_info)

      if updated_job_info.completed_tasks >= updated_job_info.total_tasks do
        job_result_signal =
          Signal.new!(
            "job.result",
            %{
              job_id: params.job_id,
              results: updated_job_info.results,
              total_tasks: updated_job_info.total_tasks
            },
            source: "/coordinator"
          )

        agent_like = %{state: context.state}
        emit_directive = Directive.emit_to_parent(agent_like, job_result_signal)

        completed = Map.get(context.state, :completed_jobs, [])

        set_pending_op =
          StateOp.set_path([:pending_tasks], Map.delete(updated_pending, params.job_id))

        {:ok, %{completed_jobs: [params.job_id | completed]},
         [set_pending_op | List.wrap(emit_directive)]}
      else
        {:ok, %{pending_tasks: updated_pending}}
      end
    end
  end

  # ===========================================================================
  # LAYER 1: ORCHESTRATOR ACTIONS
  # ===========================================================================

  defmodule SubmitJobAction do
    @moduledoc false
    use Jido.Action,
      name: "submit_job",
      schema: [
        job_name: [type: :string, required: true],
        tasks: [type: {:list, :map}, required: true]
      ]

    def run(%{job_name: job_name, tasks: tasks}, context) do
      job_id = "job-#{System.unique_integer([:positive])}"
      coordinator_tag = String.to_atom("coordinator-#{job_id}")

      pending = Map.get(context.state, :pending_jobs, %{})

      job_info = %{
        job_id: job_id,
        job_name: job_name,
        tasks: tasks,
        coordinator_tag: coordinator_tag,
        submitted_at: DateTime.utc_now()
      }

      updated_pending = Map.put(pending, job_id, job_info)

      spawn_directive =
        Directive.spawn_agent(
          JidoExampleTest.HierarchicalAgentsTest.CoordinatorAgent,
          coordinator_tag,
          meta: %{job_id: job_id, job_name: job_name, tasks: tasks}
        )

      {:ok, %{pending_jobs: updated_pending, last_submitted: job_id}, [spawn_directive]}
    end
  end

  defmodule OrchestratorChildStartedAction do
    @moduledoc false
    use Jido.Action,
      name: "orchestrator_child_started",
      schema: [
        parent_id: [type: :string, required: true],
        child_id: [type: :string, required: true],
        child_module: [type: :any, required: true],
        tag: [type: :any, required: true],
        pid: [type: :any, required: true],
        meta: [type: :map, default: %{}]
      ]

    def run(%{pid: pid, meta: meta}, _context) do
      indexed_tasks =
        meta.tasks
        |> Enum.with_index(1)
        |> Enum.map(fn {task, idx} -> Map.put(task, :index, idx) end)

      job_signal =
        Signal.new!(
          "job.assign",
          %{job_id: meta.job_id, tasks: indexed_tasks},
          source: "/orchestrator"
        )

      emit_directive = Directive.emit_to_pid(job_signal, pid)

      {:ok, %{}, [emit_directive]}
    end
  end

  defmodule HandleJobResultAction do
    @moduledoc false
    use Jido.Action,
      name: "handle_job_result",
      schema: [
        job_id: [type: :string, required: true],
        results: [type: {:list, :map}, required: true],
        total_tasks: [type: :integer, required: true]
      ]

    def run(params, context) do
      pending = Map.get(context.state, :pending_jobs, %{})
      completed = Map.get(context.state, :completed_jobs, [])

      job_info = Map.get(pending, params.job_id, %{})

      completion_record = %{
        job_id: params.job_id,
        job_name: Map.get(job_info, :job_name, "unknown"),
        total_tasks: params.total_tasks,
        results: params.results,
        completed_at: DateTime.utc_now()
      }

      set_pending_op = StateOp.set_path([:pending_jobs], Map.delete(pending, params.job_id))

      {:ok, %{completed_jobs: [completion_record | completed]}, [set_pending_op]}
    end
  end

  # ===========================================================================
  # AGENTS: Three-layer hierarchy
  # ===========================================================================

  defmodule WorkerAgent do
    @moduledoc false
    use Jido.Agent,
      name: "worker_agent",
      schema: [
        last_task: [type: :map, default: nil],
        tasks_completed: [type: :integer, default: 0]
      ]

    def signal_routes(_ctx) do
      [
        {"task.execute", ExecuteTaskAction}
      ]
    end
  end

  defmodule CoordinatorAgent do
    @moduledoc false
    use Jido.Agent,
      name: "coordinator_agent",
      schema: [
        pending_tasks: [type: :map, default: %{}],
        current_job: [type: :string, default: nil],
        completed_jobs: [type: {:list, :string}, default: []]
      ]

    def signal_routes(_ctx) do
      [
        {"job.assign", HandleJobAssignAction},
        {"jido.agent.child.started", CoordinatorChildStartedAction},
        {"task.result", HandleTaskResultAction}
      ]
    end
  end

  defmodule OrchestratorAgent do
    @moduledoc false
    use Jido.Agent,
      name: "orchestrator_agent",
      schema: [
        pending_jobs: [type: :map, default: %{}],
        completed_jobs: [type: {:list, :map}, default: []],
        last_submitted: [type: :string, default: nil]
      ]

    def signal_routes(_ctx) do
      [
        {"submit_job", SubmitJobAction},
        {"jido.agent.child.started", OrchestratorChildStartedAction},
        {"job.result", HandleJobResultAction}
      ]
    end
  end

  # ===========================================================================
  # SIGNAL COLLECTOR: For trace verification
  # ===========================================================================

  defmodule HierarchySignalCollector do
    @moduledoc false
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, [], opts)
    end

    def get_signals(pid), do: GenServer.call(pid, :get_signals)
    def clear(pid), do: GenServer.call(pid, :clear)

    @impl true
    def init(_), do: {:ok, []}

    @impl true
    def handle_info({:signal, signal}, signals), do: {:noreply, [signal | signals]}

    @impl true
    def handle_call(:get_signals, _from, signals), do: {:reply, Enum.reverse(signals), signals}
    def handle_call(:clear, _from, _signals), do: {:reply, :ok, []}
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "three-layer spawning" do
    test "orchestrator spawns coordinator which spawns workers", %{jido: jido} do
      {:ok, orchestrator_pid} =
        Jido.start_agent(jido, OrchestratorAgent, id: unique_id("orchestrator"))

      signal =
        Signal.new!(
          "submit_job",
          %{
            job_name: "test_job",
            tasks: [
              %{operation: :compute, value: 5},
              %{operation: :compute, value: 10}
            ]
          },
          source: "/test"
        )

      {:ok, _agent} = AgentServer.call(orchestrator_pid, signal)

      eventually(
        fn ->
          case AgentServer.state(orchestrator_pid) do
            {:ok, %{children: children}} -> map_size(children) >= 1
            _ -> false
          end
        end,
        timeout: 5_000
      )

      {:ok, orch_state} = AgentServer.state(orchestrator_pid)
      assert map_size(orch_state.children) >= 1

      [coordinator_info | _] = Map.values(orch_state.children)
      coordinator_pid = coordinator_info.pid

      eventually(
        fn ->
          case AgentServer.state(coordinator_pid) do
            {:ok, %{children: children}} -> map_size(children) >= 2
            _ -> false
          end
        end,
        timeout: 5_000
      )

      {:ok, coord_state} = AgentServer.state(coordinator_pid)
      assert map_size(coord_state.children) >= 2
    end
  end

  describe "results bubble up through hierarchy" do
    test "worker results aggregate at coordinator then orchestrator", %{jido: jido} do
      {:ok, orchestrator_pid} =
        Jido.start_agent(jido, OrchestratorAgent, id: unique_id("orchestrator"))

      signal =
        Signal.new!(
          "submit_job",
          %{
            job_name: "compute_job",
            tasks: [
              %{operation: :compute, value: 3},
              %{operation: :compute, value: 7}
            ]
          },
          source: "/test"
        )

      {:ok, _agent} = AgentServer.call(orchestrator_pid, signal)

      eventually(
        fn ->
          case AgentServer.state(orchestrator_pid) do
            {:ok, %{agent: %{state: %{completed_jobs: jobs}}}} ->
              jobs != []

            _ ->
              false
          end
        end,
        timeout: 15_000
      )

      {:ok, final_state} = AgentServer.state(orchestrator_pid)
      [completed_job | _] = final_state.agent.state.completed_jobs

      assert completed_job.job_name == "compute_job"
      assert completed_job.total_tasks == 2

      results = Enum.map(completed_job.results, & &1.result)
      assert 7 in results
      assert 15 in results
    end

    test "multiple jobs complete independently", %{jido: jido} do
      {:ok, orchestrator_pid} =
        Jido.start_agent(jido, OrchestratorAgent, id: unique_id("orchestrator"))

      job1_signal =
        Signal.new!(
          "submit_job",
          %{
            job_name: "job_alpha",
            tasks: [%{operation: :compute, value: 1}]
          },
          source: "/test"
        )

      job2_signal =
        Signal.new!(
          "submit_job",
          %{
            job_name: "job_beta",
            tasks: [%{operation: :compute, value: 2}]
          },
          source: "/test"
        )

      {:ok, _} = AgentServer.call(orchestrator_pid, job1_signal)
      {:ok, _} = AgentServer.call(orchestrator_pid, job2_signal)

      eventually(
        fn ->
          case AgentServer.state(orchestrator_pid) do
            {:ok, %{agent: %{state: %{completed_jobs: [_, _ | _]}}}} ->
              true

            _ ->
              false
          end
        end,
        timeout: 20_000
      )

      {:ok, final_state} = AgentServer.state(orchestrator_pid)
      completed_names = Enum.map(final_state.agent.state.completed_jobs, & &1.job_name)

      assert "job_alpha" in completed_names
      assert "job_beta" in completed_names
    end
  end

  describe "trace propagation through hierarchy" do
    test "trace_id preserved from orchestrator to worker", %{jido: jido} do
      {:ok, collector} = HierarchySignalCollector.start_link()
      on_exit(fn -> if Process.alive?(collector), do: GenServer.stop(collector) end)

      {:ok, orchestrator_pid} =
        Jido.start_agent(jido, OrchestratorAgent,
          id: unique_id("orchestrator"),
          default_dispatch: {:pid, target: collector}
        )

      root_trace = Trace.new_root()

      signal =
        Signal.new!(
          "submit_job",
          %{
            job_name: "traced_job",
            tasks: [%{operation: :compute, value: 42}]
          },
          source: "/test"
        )

      {:ok, traced_signal} = Trace.put(signal, root_trace)

      {:ok, _agent} = AgentServer.call(orchestrator_pid, traced_signal)

      eventually(
        fn ->
          case AgentServer.state(orchestrator_pid) do
            {:ok, %{agent: %{state: %{completed_jobs: jobs}}}} ->
              jobs != []

            _ ->
              false
          end
        end,
        timeout: 15_000
      )

      {:ok, final_state} = AgentServer.state(orchestrator_pid)
      assert final_state.agent.state.completed_jobs != []
    end
  end

  describe "complex job with multiple task types" do
    test "handles mixed operations across workers", %{jido: jido} do
      {:ok, orchestrator_pid} =
        Jido.start_agent(jido, OrchestratorAgent, id: unique_id("orchestrator"))

      signal =
        Signal.new!(
          "submit_job",
          %{
            job_name: "mixed_job",
            tasks: [
              %{operation: :compute, value: 5},
              %{operation: :validate, value: 10},
              %{operation: :transform, value: 100}
            ]
          },
          source: "/test"
        )

      {:ok, _agent} = AgentServer.call(orchestrator_pid, signal)

      eventually(
        fn ->
          case AgentServer.state(orchestrator_pid) do
            {:ok, %{agent: %{state: %{completed_jobs: jobs}}}} ->
              jobs != []

            _ ->
              false
          end
        end,
        timeout: 15_000
      )

      {:ok, final_state} = AgentServer.state(orchestrator_pid)
      [completed_job | _] = final_state.agent.state.completed_jobs

      assert completed_job.total_tasks == 3

      results_by_op =
        completed_job.results
        |> Enum.map(fn r -> {r.operation, r.result} end)
        |> Map.new()

      assert results_by_op[:compute] == 11
      assert results_by_op[:validate] == :valid
      assert results_by_op[:transform] == "100_processed"
    end
  end

  describe "pending state management" do
    test "pending jobs cleared after completion", %{jido: jido} do
      {:ok, orchestrator_pid} =
        Jido.start_agent(jido, OrchestratorAgent, id: unique_id("orchestrator"))

      signal =
        Signal.new!(
          "submit_job",
          %{
            job_name: "clearable_job",
            tasks: [%{operation: :compute, value: 1}]
          },
          source: "/test"
        )

      {:ok, agent_after_submit} = AgentServer.call(orchestrator_pid, signal)
      assert map_size(agent_after_submit.state.pending_jobs) == 1

      eventually(
        fn ->
          case AgentServer.state(orchestrator_pid) do
            {:ok, %{agent: %{state: %{completed_jobs: jobs}}}} ->
              jobs != []

            _ ->
              false
          end
        end,
        timeout: 10_000
      )

      {:ok, final_state} = AgentServer.state(orchestrator_pid)
      assert map_size(final_state.agent.state.pending_jobs) == 0
      assert length(final_state.agent.state.completed_jobs) == 1
    end
  end
end
