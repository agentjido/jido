defmodule JidoTest.AgentServerRuntimeFixtures do
  alias Jido.AgentServer, as: Server
  alias Jido.Signal

  defmodule OwnedExecutionAction do
    use Jido.Action, name: "agent_owned_execution"

    @impl true
    def run(%{test: test, gate: gate, label: label}, context) do
      send(test, {:owned_execution, label, self()})

      receive do
        {:release, ^gate} -> {:ok, context.agent_state}
      end
    end
  end

  defmodule OwnedExecutionFlow do
    use Jido.Flow, name: "agent_owned_execution_flow"

    flow do
      step "owned",
        action: OwnedExecutionAction,
        params: %{test: input(:test), gate: input(:gate), label: input(:label)}

      output result("owned")
    end
  end

  defmodule OwnedExecutionAgent do
    use Jido.Agent,
      name: "agent_owned_execution_agent",
      routes: [
        {"owned.action", OwnedExecutionAction},
        {"owned.flow", OwnedExecutionFlow}
      ]
  end

  defmodule ObservedExec do
    def run_async(executable, input, context, opts) do
      test = Map.get(input, :test) || get_in(input, [:signal, Access.key(:data), :test])
      Process.put(__MODULE__, test)
      Jido.Exec.run_async(executable, input, context, opts)
    end

    def handle_message(handle, message) do
      send(Process.get(__MODULE__), {:exec_message, message})
      Jido.Exec.handle_message(handle, message)
    end

    defdelegate cancel(handle), to: Jido.Exec
  end

  defmodule CountedDirective do
    defstruct [:test]
  end

  defmodule ReturnCountedDirective do
    use Jido.Action, name: "agent_return_counted_directive"

    @impl Jido.Action
    def run(%{test: test}, context) do
      {:ok, context.agent_state, [%CountedDirective{test: test}]}
    end
  end

  defmodule CountedDirectivePlugin do
    use Jido.Plugin

    @impl true
    def prepare(command, _opts) do
      {:ok, %{command | signal: %{command.signal | source: "/plugin-prepared"}}}
    end

    @impl true
    def directives(_opts), do: [CountedDirective]

    @impl true
    def validate_directive(%CountedDirective{test: test} = directive, _opts) do
      send(test, :directive_validated)
      {:ok, directive}
    end

    @impl true
    def dispatch(_runtime, %CountedDirective{test: test}, context, _opts) do
      send(test, {:directive_dispatched, context})
      :ok
    end

    def child_spec(_init) do
      Supervisor.child_spec({Elixir.Agent, fn -> nil end}, id: __MODULE__)
    end
  end

  defmodule CountedDirectiveAgent do
    use Jido.Agent,
      name: "counted_directive_agent",
      routes: [{"directive.count", ReturnCountedDirective}],
      plugins: [CountedDirectivePlugin]
  end

  defmodule SlowDirective do
    defstruct [:test, :gate, :server]
  end

  defmodule ReturnSlowDirective do
    use Jido.Action, name: "agent_return_slow_directive"

    @impl Jido.Action
    def run(%{test: test} = params, context) do
      directive = %SlowDirective{
        test: test,
        gate: Map.get(params, :gate),
        server: Map.get(params, :server)
      }

      {:ok, context.agent_state, [directive]}
    end
  end

  defmodule SlowDirectivePlugin do
    use Jido.Plugin

    @impl true
    def directives(_opts), do: [SlowDirective]

    @impl true
    def validate_directive(%SlowDirective{} = directive, _opts), do: {:ok, directive}

    @impl true
    def dispatch(_runtime, %SlowDirective{test: test, gate: gate}, _context, _opts)
        when not is_nil(gate) do
      send(test, {:plugin_directive_blocked, gate, self()})

      receive do
        {:release, ^gate} -> :ok
      end
    end

    def dispatch(_runtime, %SlowDirective{test: test, server: server}, _context, _opts)
        when is_pid(server) do
      signal = Signal.new!("directive.slow", %{test: test}, source: "/plugin/directive")
      send(test, {:plugin_directive_reentry, Server.call(server, signal)})
      :ok
    end

    def child_spec(_init) do
      Supervisor.child_spec({Elixir.Agent, fn -> nil end}, id: __MODULE__)
    end
  end

  defmodule SlowDirectiveAgent do
    use Jido.Agent,
      name: "slow_directive_agent",
      routes: [{"directive.slow", ReturnSlowDirective}],
      plugins: [SlowDirectivePlugin]
  end

  defmodule ReadinessRuntime do
    use GenServer

    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    @impl true
    def init(init), do: {:ok, init, {:continue, :initialize}}

    @impl true
    def handle_continue(:initialize, init) do
      test = Process.whereis(:jido_agent_plugin_readiness_test)
      send(test, {:plugin_initializing, self()})

      receive do
        :release -> {:noreply, init}
      end
    end

    @impl true
    def handle_call(:await_ready, _from, state), do: {:reply, :ok, state}
  end

  defmodule ReadinessPlugin do
    use Jido.Plugin

    @impl true
    def await_ready(runtime, _opts), do: GenServer.call(runtime, :await_ready)

    def child_spec(init) do
      Supervisor.child_spec({ReadinessRuntime, init}, id: __MODULE__)
    end
  end

  defmodule ReadinessAgent do
    use Jido.Agent,
      name: "readiness_agent",
      plugins: [ReadinessPlugin]
  end

  defmodule GenerationRuntime do
    use GenServer

    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    @impl true
    def init(init) do
      notify({:generation_started, self()})
      {:ok, init}
    end

    @impl true
    def terminate(_reason, _state) do
      case Process.whereis(:jido_agent_generation_test) do
        nil ->
          :ok

        test ->
          send(test, {:generation_stopping, self()})
          owner_ref = Process.monitor(test)

          receive do
            :release_generation_stop -> :ok
            {:DOWN, ^owner_ref, :process, ^test, _reason} -> :ok
          after
            2_000 -> :ok
          end

          Process.demonitor(owner_ref, [:flush])
      end
    end

    defp notify(message) do
      if test = Process.whereis(:jido_agent_generation_test), do: send(test, message)
      :ok
    end
  end

  defmodule GenerationPlugin do
    use Jido.Plugin

    def child_spec(init) do
      Supervisor.child_spec({GenerationRuntime, init}, id: __MODULE__)
    end
  end

  defmodule GenerationAgent do
    use Jido.Agent,
      name: "generation_agent",
      plugins: [GenerationPlugin]
  end

  defmodule FreshRuntimeDirective do
    defstruct [:value]
  end

  defmodule ReturnFreshRuntimeDirective do
    use Jido.Action, name: "agent_return_fresh_runtime_directive"

    @impl Jido.Action
    def run(%{value: value}, context) do
      {:ok, context.agent_state, [%FreshRuntimeDirective{value: value}]}
    end
  end

  defmodule FreshRuntimePlugin do
    use GenServer
    use Jido.Plugin

    @impl Jido.Plugin
    def state_spec(_opts) do
      {:fresh_runtime,
       Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)}) |> Zoi.default(%{value: 0})}
    end

    @impl Jido.Plugin
    def update_state(state, [%FreshRuntimeDirective{value: value}], _opts) do
      {:ok, %{state | value: value}}
    end

    @impl Jido.Plugin
    def directives(_opts), do: [FreshRuntimeDirective]

    @impl Jido.Plugin
    def validate_directive(%FreshRuntimeDirective{} = directive, _opts),
      do: {:ok, directive}

    @impl Jido.Plugin
    def dispatch(_runtime, _directive, _context, _opts), do: :ok

    @impl Jido.Plugin
    def await_ready(runtime, _opts) do
      if :persistent_term.get({__MODULE__, :pause_restart}, false),
        do: notify({:fresh_readiness_waiting, self(), runtime})

      GenServer.call(runtime, :await_ready)
    end

    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    @impl GenServer
    def init(init), do: {:ok, %{init: init, plugin_state: nil}, {:continue, :load_state}}

    @impl GenServer
    def handle_continue(:load_state, state) do
      if :persistent_term.get({__MODULE__, :pause_restart}, false) do
        notify({:fresh_load_waiting, self()})

        receive do
          :release_fresh_load -> :ok
        end
      end

      {:ok, plugin_state} = Jido.Plugin.state(state.init)
      notify({:fresh_runtime_started, self(), plugin_state})
      {:noreply, %{state | plugin_state: plugin_state}}
    end

    @impl GenServer
    def handle_call(:await_ready, _from, state) do
      notify({:fresh_runtime_ready, self(), state.plugin_state})
      {:reply, :ok, state}
    end

    defp notify(message) do
      if test = Process.whereis(:jido_agent_fresh_runtime_test), do: send(test, message)
      :ok
    end
  end

  defmodule FreshRuntimeAgent do
    use Jido.Agent,
      name: "fresh_runtime_agent",
      routes: [{"runtime.fresh", ReturnFreshRuntimeDirective}],
      plugins: [FreshRuntimePlugin]
  end
end
