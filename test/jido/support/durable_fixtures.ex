defmodule JidoTest.DurableFixtures do
  @moduledoc false

  defmodule Probe do
    use GenServer
    def start_link(observer), do: GenServer.start_link(__MODULE__, observer, name: __MODULE__)
    def configure(mode), do: GenServer.call(__MODULE__, {:configure, mode})
    def enter(step), do: GenServer.call(__MODULE__, {:enter, step}, :infinity)
    def hook, do: GenServer.call(__MODULE__, :hook, :infinity)
    def hook_count, do: GenServer.call(__MODULE__, :hook_count)
    def gate(kind), do: GenServer.call(__MODULE__, {:gate, kind}, :infinity)
    def records, do: GenServer.call(__MODULE__, :records)
    def checkpoint, do: GenServer.call(__MODULE__, :checkpoint)
    def release, do: GenServer.call(__MODULE__, :release)

    def init(observer),
      do: {:ok, %{observer: observer, started: [], hooks: 0, mode: :pass, waiter: nil}}

    def handle_call({:configure, mode}, _, state), do: {:reply, :ok, %{state | mode: mode}}
    def handle_call(:records, _, state), do: {:reply, state.started, state}
    def handle_call(:hook_count, _, state), do: {:reply, state.hooks, state}

    def handle_call(
          :checkpoint,
          _,
          %{mode: :reject_checkpoint, started: [1, 2, 3, 4, 5]} = state
        ),
        do: {:reply, {:error, {:rejected, :offline}}, %{state | mode: :pass}}

    def handle_call(:checkpoint, _, state), do: {:reply, :ok, state}

    def handle_call({:enter, step}, from, state) do
      state = %{state | started: state.started ++ [step]}
      if step == 6, do: hold(state, from, :step_6), else: {:reply, :ok, state}
    end

    def handle_call(:hook, from, state) do
      state = %{state | hooks: state.hooks + 1}

      case state.mode do
        :hook_gate -> hold(state, from, :hook)
        _ -> {:reply, :ok, state}
      end
    end

    def handle_call({:gate, {kind, module}}, from, state) do
      if state.mode in [kind, {kind, module}],
        do: hold(%{state | mode: :pass}, from, kind),
        else: {:reply, :ok, state}
    end

    def handle_call(:release, _, state) do
      if state.waiter, do: GenServer.reply(state.waiter, :ok)
      {:reply, :ok, %{state | waiter: nil}}
    end

    defp hold(state, from, kind) do
      if state.observer, do: send(state.observer, {:durable_barrier, kind, elem(from, 0)})
      {:noreply, %{state | waiter: from}}
    end
  end

  defmodule Step do
    use Jido.Action,
      name: "durable_probe_step",
      schema: Zoi.object(%{step: Zoi.integer(), value: Zoi.integer()})

    def run(input, _) do
      :ok = Probe.enter(input.step)
      {:ok, %{value: input.value + 1}}
    end
  end

  defmodule Flow do
    use Jido.Flow,
      name: "durable_probe_flow",
      schema: Zoi.object(%{value: Zoi.integer()}),
      output_schema: Zoi.object(%{count: Zoi.integer()})

    flow do
      step "one", action: Step, params: %{step: 1, value: input(:value)}
      step "two", action: Step, params: %{step: 2, value: result("one", :value)}
      step "three", action: Step, params: %{step: 3, value: result("two", :value)}
      step "four", action: Step, params: %{step: 4, value: result("three", :value)}
      step "five", action: Step, params: %{step: 5, value: result("four", :value)}
      step "six", action: Step, params: %{step: 6, value: result("five", :value)}
      step "seven", action: Step, params: %{step: 7, value: result("six", :value)}
      step "eight", action: Step, params: %{step: 8, value: result("seven", :value)}
      step "nine", action: Step, params: %{step: 9, value: result("eight", :value)}
      step "ten", action: Step, params: %{step: 10, value: result("nine", :value)}
      output %{count: result("ten", :value)}
    end
  end

  defmodule Hook do
    use Jido.Plugin
    def after_commit(_, _, _), do: Probe.hook()
  end

  defmodule BadOutput do
    use Jido.Flow, name: "durable_bad_output", schema: Zoi.object(%{})

    flow do
      step "pid", _input <- input() do
        {:ok, %{pid: self()}}
      end

      output result("pid")
    end
  end

  defmodule EffectsFlow do
    use Jido.Flow, name: "durable_effects_flow", schema: Zoi.object(%{})

    flow do
      step "effect", _input <- input() do
        {:ok, %{}, [:unexpected_effect]}
      end

      output result("effect")
    end
  end

  defmodule TopologyFlow do
    use Jido.Flow, name: "durable_topology_mutation", schema: Zoi.object(%{})

    flow do
      step "add_agent", _input <- input() do
        {:ok, %{count: 1},
         [Jido.Agent.Directive.agent_add(:nested, JidoTest.DurableFixtures.Worker)]}
      end

      output result("add_agent")
    end
  end

  defmodule Corrupt do
    @behaviour Jido.Persistence.Adapter

    def get(key, opts) do
      case Jido.Persistence.File.get(key, opts) do
        {:ok, bytes} = result -> corrupt(bytes, result)
        error -> error
      end
    end

    defp corrupt(bytes, result) do
      case :erlang.binary_to_term(bytes) do
        %{fmt: 1, log: log} when is_list(log) -> {:ok, :erlang.term_to_binary(%{fmt: 99})}
        _ -> result
      end
    end

    def compare_and_swap(key, expected, value, opts),
      do: Jido.Persistence.File.compare_and_swap(key, expected, value, opts)
  end

  defmodule Storage do
    @behaviour Jido.Persistence.Adapter
    def get(key, opts), do: Jido.Persistence.File.get(key, opts)

    def compare_and_swap(key, expected, value, opts) do
      record = :erlang.binary_to_term(value, [:safe])

      kind =
        case record do
          %{server_turn: %{status: :completed}} -> :completion_write
          %{rev: 1} -> :intent_write
          %{fmt: 1, log: nil} -> :checkpoint_create
          %{fmt: 1, log: log} when is_list(log) -> :input_write
          _ -> :other
        end

      with :ok <- Probe.checkpoint(),
           :ok <- Jido.Persistence.File.compare_and_swap(key, expected, value, opts) do
        Probe.gate({kind, Map.get(record, :agent_module)})
      end
    end
  end

  defmodule Reject do
    @behaviour Jido.Persistence.Adapter
    def get(key, opts), do: Jido.Persistence.File.get(key, opts)

    def compare_and_swap(key, expected, value, opts) do
      case :erlang.binary_to_term(value, [:safe]) do
        %{rev: revision} when revision > 0 -> {:error, {:rejected, :offline}}
        _ -> Jido.Persistence.File.compare_and_swap(key, expected, value, opts)
      end
    end
  end

  defmodule Worker do
    use Jido.Agent, name: "durable_probe_agent"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      route "request", Flow
      route "bad_output", BadOutput
      route "effects", EffectsFlow
      route "topology", TopologyFlow

      route "increment" do
        action _input, context: context do
          {:ok, %{context.agent_state | count: context.agent_state.count + 1}}
        end
      end

      route "mutate" do
        action input, context: context do
          {:ok, context.agent_state, input.directives}
        end
      end
    end
  end

  defmodule Team do
    use Jido.Agent, name: "durable_probe_team"

    routes do
      route "request"

      route "mutate" do
        action input, context: context do
          {:ok, context.agent_state, input.directives}
        end
      end
    end

    topology do
      agent :worker, Worker
      agent :sibling, Worker

      connections do
        connect "request", from: :root, to: :worker
      end
    end
  end

  def member(server, name) do
    [pid] = Jido.AgentServer.members(server, name)
    pid
  end
end
