defmodule Jido.Exec.Runner.ManagedTest do
  use Covenant.Case, component: "jido_action.execution", async: false
  @moduletag obligation: "jido_action.execution.I21"

  alias Jido.Error.{ExecutionError, TimeoutError}
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Jido.Instruction

  defmodule Gate do
    use GenServer

    def start_link(owner), do: GenServer.start_link(__MODULE__, owner, name: __MODULE__)
    def wait, do: GenServer.call(__MODULE__, :wait, :infinity)
    def open, do: GenServer.call(__MODULE__, :open)

    @impl GenServer
    def init(owner), do: {:ok, %{owner: owner, open?: false, waiting: []}}

    @impl GenServer
    def handle_call(:wait, from, %{open?: false} = state) do
      send(state.owner, :gate_waiting)
      {:noreply, %{state | waiting: [from | state.waiting]}}
    end

    def handle_call(:wait, _from, state), do: {:reply, :ok, state}

    def handle_call(:open, _from, state) do
      Enum.each(state.waiting, &GenServer.reply(&1, :ok))
      {:reply, :ok, %{state | open?: true, waiting: []}}
    end
  end

  defmodule First do
    use Jido.Action, name: "managed_first"

    @impl true
    def run(_params, _context), do: {:ok, %{value: 1}, [:first]}
  end

  defmodule Second do
    use Jido.Action, name: "managed_second"

    @impl true
    def run(%{value: value}, context) do
      :ok = Gate.wait()
      {:ok, %{value: value + 1, request_id: context.request_id}, [:second]}
    end
  end

  defmodule Echo do
    use Jido.Action, name: "managed_echo"

    @impl true
    def run(params, context), do: {:ok, Map.put(params, :seen, Map.has_key?(context, :api_key))}
  end

  defmodule DateTimeValue do
    use Jido.Action, name: "managed_datetime_value"

    @impl true
    def run(_params, _context), do: {:ok, %{at: ~U[2026-11-03 12:00:00Z]}}
  end

  defmodule Blocks do
    use Jido.Action, name: "managed_blocks"

    @impl true
    def run(_params, _context) do
      receive do
        :never -> {:ok, %{}}
      end
    end
  end

  defmodule Kills do
    use Jido.Action, name: "managed_kills"

    @impl true
    def run(_params, _context), do: Process.exit(self(), :kill)
  end

  defmodule LegacyStreamingStore do
    @behaviour Runic.Runner.Store

    @impl true
    def init_store(opts), do: {:ok, Keyword.fetch!(opts, :agent)}

    @impl true
    def save(id, log, agent) do
      Agent.update(agent, &put_in(&1, [:logs, id], log))
    end

    @impl true
    def load(id, agent) do
      Agent.get(agent, fn state ->
        case Map.fetch(state.logs, id) do
          {:ok, log} -> {:ok, log}
          :error -> {:error, :not_found}
        end
      end)
    end

    @impl true
    def append(id, events, agent) do
      Agent.get_and_update(agent, fn state ->
        stored = Map.get(state.events, id, []) ++ events
        {{:ok, length(stored)}, put_in(state, [:events, id], stored)}
      end)
    end

    @impl true
    def stream(id, agent) do
      Agent.get(agent, fn state ->
        case Map.fetch(state.events, id) do
          {:ok, events} -> {:ok, events}
          :error -> {:error, :not_found}
        end
      end)
    end
  end

  test "resume/4 restores context, policy, and the managed result" do
    runner = start_runner!(__MODULE__.ResumeRunner)
    start_supervised!({Gate, self()})
    id = {:resume, System.unique_integer([:positive])}
    context = %{request_id: "r-42"}
    opts = [timeout: 60_000, max_attempts: 3, max_concurrency: 1]

    assert {:ok, _worker} =
             Jido.Test.Exec.RunnerHarness.start(
               runner,
               id,
               two_step_flow(),
               %{},
               context,
               opts ++ [checkpoint_strategy: :every_cycle]
             )

    assert_receive :gate_waiting, 2_000
    assert :ok = Runic.Runner.checkpoint(runner, id)
    assert :ok = Runic.Runner.stop(runner, id, persist: true)
    :ok = Gate.open()

    test_pid = self()
    idle = [on_idle: fn _state -> send(test_pid, {:idle, id}) end]
    assert {:ok, _worker} = Jido.Test.Exec.RunnerHarness.resume(runner, id, context, opts ++ [hooks: idle])
    assert_receive {:idle, ^id}, 2_000

    assert {:ok, workflow} = Runic.Runner.get_workflow(runner, id)
    assert [default: policy] = workflow.scheduler_policies
    assert %{timeout_ms: 60_000, max_retries: 2, execution_mode: :durable} = policy

    assert Jido.Test.Exec.RunnerHarness.result(workflow) ==
             {:ok, %{value: 2, request_id: "r-42"}, [:first, :second]}

    assert Jido.Test.Exec.RunnerHarness.result(runner, id) == Jido.Test.Exec.RunnerHarness.result(workflow)
  end

  test "resume/4 keeps historical facts as references by default" do
    runner = start_runner!(__MODULE__.HybridResumeRunner)
    id = {:hybrid_resume, System.unique_integer([:positive])}

    assert {:ok, _worker} =
             Jido.Test.Exec.RunnerHarness.start(runner, id, Echo, %{value: 1}, %{}, hooks: idle_hook(id))

    assert_receive {:idle, ^id}, 2_000
    assert :ok = Runic.Runner.checkpoint(runner, id)
    assert :ok = Runic.Runner.stop(runner, id, persist: true)

    assert {:ok, worker} = Jido.Test.Exec.RunnerHarness.resume(runner, id)
    _ = :sys.get_state(worker)
    assert {:ok, workflow} = Runic.Runner.get_workflow(runner, id)

    vertices = Map.values(workflow.graph.vertices)
    assert Enum.any?(vertices, &is_struct(&1, Runic.Workflow.FactRef))
    assert Enum.any?(vertices, &is_struct(&1, Runic.Workflow.Fact))
    assert Jido.Test.Exec.RunnerHarness.result(workflow) == {:ok, %{value: 1, seen: false}}
  end

  test "resume/4 falls back to full recovery for a native Batch" do
    runner = start_runner!(__MODULE__.BatchResumeRunner)
    id = {:batch_resume, System.unique_integer([:positive])}

    flow =
      Flow.new!(%{
        name: "managed_batch_resume",
        components: [
          %{
            kind: :map,
            name: "items",
            collection: Ref.input(:items),
            action: Echo,
            params: %{value: Ref.item()}
          }
        ],
        output: %{items: Ref.result("items")}
      })

    assert {:ok, _worker} =
             Jido.Test.Exec.RunnerHarness.start(runner, id, flow, %{items: [1, 2]}, %{}, hooks: idle_hook(id))

    assert_receive {:idle, ^id}, 2_000
    assert :ok = Runic.Runner.checkpoint(runner, id)
    assert :ok = Runic.Runner.stop(runner, id, persist: true)

    for mode <- [:hybrid, :lazy] do
      assert {:error, {:unsupported_batch_rehydration, ^mode}} =
               Jido.Test.Exec.RunnerHarness.resume(runner, id, %{}, rehydration: mode)
    end

    assert {:ok, worker} = Jido.Test.Exec.RunnerHarness.resume(runner, id)
    _ = :sys.get_state(worker)
    assert {:ok, workflow} = Runic.Runner.get_workflow(runner, id)

    refute Enum.any?(workflow.graph.vertices, fn {_hash, vertex} ->
             is_struct(vertex, Runic.Workflow.FactRef)
           end)

    assert Jido.Test.Exec.RunnerHarness.result(workflow) ==
             {:ok, %{items: [%{value: 1, seen: false}, %{value: 2, seen: false}]}}
  end

  test "managed Action targets keep context out of the Runic store" do
    runner = start_runner!(__MODULE__.SecretRunner)
    id = {:secret, System.unique_integer([:positive])}

    assert {:ok, _worker} =
             Jido.Test.Exec.RunnerHarness.start(runner, id, Echo, %{value: 1}, %{api_key: "SECRET-KEY-123"},
               hooks: idle_hook(id)
             )

    assert_receive {:idle, ^id}, 2_000
    assert {:ok, workflow} = Runic.Runner.get_workflow(runner, id)
    assert Jido.Test.Exec.RunnerHarness.result(workflow) == {:ok, %{value: 1, seen: true}}

    {store, store_state} = Runic.Runner.get_store(runner)
    assert {:ok, events} = store.stream(id, store_state)
    refute inspect(Enum.to_list(events), limit: :infinity) =~ "SECRET-KEY-123"
  end

  test "managed execution keeps a DateTime Action result as a local value" do
    runner = start_runner!(__MODULE__.DateTimeRunner)
    id = {:datetime, System.unique_integer([:positive])}

    assert {:ok, _worker} =
             Jido.Test.Exec.RunnerHarness.start(runner, id, DateTimeValue, %{}, %{}, hooks: idle_hook(id))

    assert_receive {:idle, ^id}, 2_000
    assert Jido.Test.Exec.RunnerHarness.result(runner, id) == {:ok, %{at: ~U[2026-11-03 12:00:00Z]}}
  end

  test "managed execution rejects non-portable Instruction metadata" do
    runner = start_runner!(__MODULE__.MetadataRunner)
    instruction = Instruction.new!(target: Echo, metadata: %{owner: self()})

    assert {:error, %ExecutionError{details: details}} =
             Jido.Test.Exec.RunnerHarness.start(runner, {:metadata, 1}, instruction)

    assert %{reason: :non_portable_durable_value, path: [:metadata, :owner]} = details
  end

  test "resume/4 uses full recovery for a Store without fact storage" do
    agent = start_supervised!({Agent, fn -> %{events: %{}, logs: %{}} end})

    runner =
      start_runner!(__MODULE__.LegacyStreamingRunner,
        store: LegacyStreamingStore,
        store_opts: [agent: agent]
      )

    id = {:legacy_streaming, System.unique_integer([:positive])}

    assert {:ok, _worker} =
             Jido.Test.Exec.RunnerHarness.start(runner, id, Echo, %{value: 1}, %{}, hooks: idle_hook(id))

    assert_receive {:idle, ^id}, 2_000
    assert :ok = Runic.Runner.checkpoint(runner, id)
    assert :ok = Runic.Runner.stop(runner, id, persist: true)

    assert {:ok, worker} = Jido.Test.Exec.RunnerHarness.resume(runner, id)
    _ = :sys.get_state(worker)
    assert {:ok, workflow} = Runic.Runner.get_workflow(runner, id)

    refute Enum.any?(workflow.graph.vertices, fn {_hash, vertex} ->
             is_struct(vertex, Runic.Workflow.FactRef)
           end)

    assert Jido.Test.Exec.RunnerHarness.result(workflow) == {:ok, %{value: 1, seen: false}}
  end

  test "managed execution uses the package concurrency configuration" do
    previous = Application.fetch_env(:jido, :max_concurrency)
    Application.put_env(:jido, :max_concurrency, 2)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:jido, :max_concurrency, value)
        :error -> Application.delete_env(:jido, :max_concurrency)
      end
    end)

    runner = start_runner!(__MODULE__.DefaultConcurrencyRunner)
    id = {:default_concurrency, System.unique_integer([:positive])}

    assert {:ok, worker} =
             Jido.Test.Exec.RunnerHarness.start(runner, id, Echo, %{value: 1}, %{}, dispatch_mode: :manual)

    assert %{max_concurrency: 2} = :sys.get_state(worker)
  end

  test "the default executor uses a partitioned Runner Task Supervisor" do
    runner = start_runner!(__MODULE__.PartitionRunner, task_supervisor: {:partition, 2})
    id = {:partition, System.unique_integer([:positive])}

    assert {:ok, _worker} = Jido.Test.Exec.RunnerHarness.start(runner, id, Echo, %{value: 3}, %{}, hooks: idle_hook(id))
    assert_receive {:idle, ^id}, 2_000
    assert {:ok, workflow} = Runic.Runner.get_workflow(runner, id)
    assert Jido.Test.Exec.RunnerHarness.result(workflow) == {:ok, %{value: 3, seen: false}}
  end

  test "result/1 projects managed failures to public Jido errors" do
    runner = start_runner!(__MODULE__.FailureRunner)

    for {target, opts, error} <- [
          {Blocks, [timeout: 20], TimeoutError},
          {Kills, [], ExecutionError}
        ] do
      id = {:failure, System.unique_integer([:positive])}

      assert {:ok, _worker} =
               Jido.Test.Exec.RunnerHarness.start(runner, id, target, %{}, %{}, opts ++ [hooks: idle_hook(id)])

      assert_receive {:idle, ^id}, 2_000
      assert {:ok, workflow} = Runic.Runner.get_workflow(runner, id)
      assert {:error, %^error{message: message, details: details}} = Jido.Test.Exec.RunnerHarness.result(workflow)
      assert {:error, %^error{message: ^message, details: ^details}} = Jido.Test.Exec.RunnerHarness.result(runner, id)
    end
  end

  defp start_runner!(name, opts \\ []) do
    start_supervised!({Runic.Runner, Keyword.put(opts, :name, name)})
    name
  end

  defp idle_hook(id) do
    test_pid = self()
    [on_idle: fn _state -> send(test_pid, {:idle, id}) end]
  end

  defp two_step_flow do
    Flow.new!(%{
      name: "managed_two_step",
      components: [
        %{kind: :step, name: "first", action: First, params: %{}},
        %{
          kind: :step,
          name: "second",
          action: Second,
          params: %{value: Ref.result("first", :value)}
        }
      ],
      output: Ref.result("second")
    })
  end
end
