defmodule JidoTest.AgentServer.Fixtures do
  @moduledoc false
  import ExUnit.Assertions
  import ExUnit.Callbacks
  alias Jido.AgentServer, as: Server

  defmodule Effect do
    @moduledoc false
    use Jido.Agent.Directive
    defstruct [:label, :observer, mode: :ok]
  end

  defmodule ControlStorage do
    @moduledoc false
    @behaviour Jido.Persistence.Adapter

    def get(key, opts), do: JidoTest.Persistence.ProbeStore.get(key, opts)

    def compare_and_swap(key, expected, value, opts) do
      case Elixir.Agent.get(opts[:control], & &1) do
        :gate ->
          send(opts[:observer], {:saving, self()})
          receive do: (:release -> store(key, expected, value, opts))

        :probe ->
          server = opts[:server].()

          send(
            opts[:observer],
            {:storage_probe, Server.quiesce(server, timeout: 100),
             Server.hibernate(server, timeout: 100), Server.resume(server, 100),
             Server.stop(server, :shutdown, 100)}
          )

          store(key, expected, value, opts)

        :ok ->
          store(key, expected, value, opts)

        error ->
          error
      end
    end

    defp store(key, expected, value, opts),
      do: JidoTest.Persistence.ProbeStore.compare_and_swap(key, expected, value, opts)
  end

  defmodule ShutdownResource do
    @moduledoc false
    use GenServer
    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    def init(init) do
      Process.flag(:trap_exit, true)
      {:ok, init}
    end

    def terminate(_, init) do
      send(init.options[:observer], {:closing, self()})
      receive do: (:release -> :ok)
    end
  end

  defmodule ShutdownPlugin do
    @moduledoc false
    use Jido.Plugin

    def child_spec(init),
      do: %{start: {ShutdownResource, :start_link, [init]}, shutdown: 5_000}
  end

  defmodule Work do
    @moduledoc false
    alias Jido.Action.Error, as: ActionError
    alias JidoTest.AgentServer.Fixtures

    use Jido.Action,
      name: "server_contract_work"

    def run(input, context) do
      if context[:observer] do
        # Observation is not ownership. This must not reject the external caller.
        Process.monitor(context.observer)
        send(context.observer, {:executing, self(), context, input})
      end

      case input[:mode] do
        :gate ->
          receive do
            :release -> :ok
          end

        :probe ->
          check = fn ->
            server = context.server
            signal = Fixtures.signal()

            results = [
              Server.call(server, signal, timeout: 500),
              server |> Server.submit(signal) |> Server.await(500),
              Server.cancel(server, 500),
              Server.cancel_turn(server, context.turn_id, 500)
            ]

            {results, Server.agent(server).id}
          end

          direct = check.()
          nested = Task.async(check) |> Task.await(1_000)
          send(context.observer, {:probe, direct, nested})

        _ ->
          :ok
      end

      result(input, context)
    end

    defp result(%{mode: :retry} = input, context) do
      attempt = Agent.get_and_update(context.counter, &{&1 + 1, &1 + 1})
      send(context.observer, {:attempt, attempt, System.monotonic_time(:millisecond)})

      if attempt <= input.failures,
        do: {:error, ActionError.execution_error("controlled failure", %{retry: input.retry})},
        else: increment(input, context)
    end

    defp result(%{mode: :trace} = input, context) do
      send(context.observer, {:trace, context.trace_context, Logger.metadata()})
      increment(input, context)
    end

    defp result(%{mode: :fail}, _context),
      do: {:error, %{private_value: "SERVER2_PRIVATE_ERROR"}}

    defp result(%{mode: :invalid}, _context), do: {:ok, %{count: "invalid"}}

    defp result(%{mode: :directive}, context),
      do: {:ok, context.agent_state, [%Fixtures.Effect{label: :returned}]}

    defp result(%{mode: :batch, directives: directives} = input, context) do
      {:ok, state} = increment(input, context)
      {:ok, state, directives}
    end

    defp result(input, context), do: increment(input, context)

    defp increment(input, context),
      do: {:ok, %{context.agent_state | count: context.agent_state.count + input[:amount]}}
  end

  defmodule Flow do
    @moduledoc false
    use Jido.Flow,
      name: "server_contract_flow"

    flow do
      step "work", action: Work, params: input()
      output result("work")
    end
  end

  defmodule Parallel do
    @moduledoc false
    use Jido.Flow,
      name: "server_contract_parallel"

    flow do
      step "left", action: Work, params: input()
      step "right", action: Work, params: input()
      output result("right")
    end
  end

  defmodule Gate do
    @moduledoc false
    use Jido.Plugin
    def state_spec(_), do: {:probe, Zoi.integer() |> Zoi.default(0)}
    def directives(_), do: [Effect]

    def prepare(preparation, _) do
      gate(preparation.signal, :preparing)
      {:ok, nil}
    end

    def reduce(reduction, _) do
      gate(reduction.signal, :settling)
      {:ok, reduction.plugin_state}
    end

    defp gate(signal, stage) do
      if signal.data[:stage] == stage do
        send(signal.data.observer, {:lifecycle_gate, stage, self()})

        receive do
          :release -> :ok
        end
      end
    end
  end

  def agent do
    Jido.Agent.define!(%{
      name: "server_contract",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      extensions: [%{id: Gate.id(), provider: Gate, vsn: Gate.vsn(), data: %{}}],
      routes: [
        %{
          path: "work",
          handler: %{kind: :action, target: Work},
          state: %{source: :output, path: []}
        },
        %{
          path: "flow",
          handler: %{kind: :flow, target: Flow},
          state: %{source: :output, path: []}
        },
        %{
          path: "parallel",
          handler: %{kind: :flow, target: Parallel},
          state: %{source: :output, path: []}
        }
      ]
    })
    |> Jido.Agent.instantiate!(id: "server-contract-instance")
  end

  def setup_runtime do
    # Use a separate Runner per test. No AgentServer is started by this fixture.
    name = Module.concat(__MODULE__, "Runner#{System.unique_integer([:positive])}")
    start_supervised!({Runic.Runner, name: name, store: Server.Store})
    %{runner: name, agent: agent()}
  end

  def start(context, opts \\ []) do
    context |> start_activation(opts) |> Server.Supervisor.worker()
  end

  def start_activation(context, opts \\ []) do
    opts = Keyword.merge([agent: context.agent, runner: context.runner], opts)

    {:ok, root} =
      start_supervised(Supervisor.child_spec({Server, opts}, id: make_ref(), restart: :temporary))

    root
  end

  def persistent(context, opts \\ []) do
    source =
      {ControlStorage,
       [
         store: context.store,
         control: context.control,
         observer: self(),
         server: fn -> Server.whereis(context.jido, context.agent.id) end
       ]}

    server =
      start(
        context,
        Keyword.merge(
          [
            jido: context.jido,
            runner: Jido.exec_runner_name(context.jido),
            persistence: source
          ],
          opts
        )
      )

    assert :ok = Server.await_ready(server)
    {server, source}
  end

  def storage_mode(context, value),
    do: Elixir.Agent.update(context.control, fn _ -> value end)

  def closed(server),
    do:
      JidoTest.Eventually.eventually(fn -> Server.status(server).admission.mode == :quiescing end)

  def replacement(root, old) do
    JidoTest.Eventually.eventually(fn ->
      pid = Server.Supervisor.worker(root)
      if is_pid(pid) and pid != old, do: pid
    end)
  end

  def signal(input \\ %{}, type \\ "work") do
    Jido.Signal.new!(type, Map.merge(%{amount: 1}, input), source: "/server-contract")
  end

  def blocked(server, runner, type \\ "work") do
    pending = Server.submit(server, signal(%{mode: :gate}, type), context: %{observer: self()})
    assert_receive {:executing, action, context, _input}, 1_000
    worker = Runic.Runner.lookup(runner, context.turn_id)
    assert is_pid(worker)
    %{pending: pending, action: action, worker: worker, id: context.turn_id}
  end

  def release(turn), do: send(turn.action, :release)

  def clean(runner) do
    assert DynamicSupervisor.which_children(Module.concat(runner, WorkerSupervisor)) == []
    assert Task.Supervisor.children(Module.concat(runner, TaskSupervisor)) == []
    {store, state} = Runic.Runner.get_store(runner)

    if function_exported?(store, :list, 1), do: assert({:ok, []} = store.list(state))
  end

  def down(pid) do
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
  end

  def unchanged(server, agent) do
    assert Server.agent(server) === agent
    assert %{phase: :idle, state_version: 0, active: nil} = Server.status(server)
  end

  def barrier(server), do: Server.call(server, signal(%{}, "missing"), timeout: 1_000)

  def elapsed(milliseconds) do
    ref = :erlang.start_timer(milliseconds, self(), :budget)
    assert_receive {:timeout, ^ref, :budget}, 1_000
  end
end
