# Experimental AgentServer2 demo. Run from the jido package:
# mix run --no-start agent_server2_demo.exs
# Covers features 1–40, stable Refs, and the activation lifetime APIs. Each section checks its results and prints PASS.
# The message barrier is only for this smoke demo. It controls turn completion
# without work-completion sleeps. Includes live Plugins and post-commit effects.
defmodule AgentServer2Demo.Counter do
  use Jido.Agent, name: "server2_demo_counter"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/server2-demo"

    route "demo.add", as: :add do
      action %{amount: amount},
        schema: Zoi.object(%{amount: Zoi.integer()}),
        context: context do
        # Observing a caller's lifetime does not make that caller owned work.
        Process.monitor(context.demo_pid)
        send(context.demo_pid, {:turn_ready, self(), context.turn_id, context.tag})

        receive do
          :continue -> {:ok, %{count: context.agent_state.count + amount}}
        after
          5_000 -> {:error, :demo_release_timeout}
        end
      end
    end

    route "demo.effects", as: :effects do
      action _input, context: context do
        directives =
          for label <- [1, 2] do
            signal = Jido.Signal.new!("demo.effect", %{label: label}, source: "/server2-demo")

            %Jido.Agent.Directive.Emit{
              signal: signal,
              dispatch: {:pid, target: context.sink, delivery_mode: :sync}
            }
          end

        {:ok, %{count: context.agent_state.count + 1}, directives}
      end
    end

    route "demo.fail", as: :fail do
      action _input do
        {:error, %{api_key: "demo-private-value", request_body: "demo-private-body"}}
      end
    end

    route "demo.reentrant", as: :probe do
      action _input, context: context do
        signal = Jido.Signal.new!("demo.reentrant", %{}, source: "/server2-demo")
        {:error, :reentrant_turn} = Jido.AgentServer2.call(context.server, signal)
        pending = Jido.AgentServer2.submit(context.server, signal)
        {:error, :reentrant_turn} = Jido.AgentServer2.await(pending)
        {:error, :reentrant_turn} = Jido.AgentServer2.cancel(context.server)

        {:error, :reentrant_turn} =
          Jido.AgentServer2.cancel_turn(context.server, context.turn_id)

        task =
          Task.async(fn ->
            {:error, :reentrant_turn} = Jido.AgentServer2.call(context.server, signal)
            pending = Jido.AgentServer2.submit(context.server, signal)
            {:error, :reentrant_turn} = Jido.AgentServer2.await(pending)
            {:error, :reentrant_turn} = Jido.AgentServer2.cancel(context.server)

            {:error, :reentrant_turn} =
              Jido.AgentServer2.cancel_turn(context.server, context.turn_id)

            :ok
          end)

        :ok = Task.await(task)
        {:ok, context.agent_state}
      end
    end
  end
end

defmodule AgentServer2Demo.PluginEffect do
  use Jido.Agent.Directive
  defstruct [:label]
end

defmodule AgentServer2Demo.LivePlugin do
  use Jido.Plugin
  def state_spec(_), do: {:resource, Zoi.integer() |> Zoi.default(7)}
  def directives(_), do: [AgentServer2Demo.PluginEffect]

  def after_commit(root, commit, opts) do
    # Finish linked child work before returning from a callback.
    Task.async(fn ->
      true = Process.alive?(root)
      send(opts[:observer], {:plugin_committed, commit.state_version, commit.plugin_state})
      :ok
    end)
    |> Task.await()
  end

  def dispatch(root, directive, context, opts) do
    true = Process.alive?(root)
    send(opts[:observer], {:plugin_effect, directive.label, context.state_version})
    :ok
  end

  def child_spec(init),
    do: %{id: __MODULE__, start: {__MODULE__.Root, :start_link, [init]}, shutdown: 50}

  def await_ready(root, opts) do
    send(opts[:observer], {:plugin_waiting, self(), root})

    receive do
      :release -> :ok
    end
  end

  def admit(root, admission, opts) do
    observer = Process.whereis(opts[:observer])
    send(observer, {:plugin_admitted, admission.state_version})
    {:ok, %{root: root, observer: observer}}
  end

  defmodule Root do
    def start_link(_init) do
      starter = self()

      {:ok, pid} =
        Task.start_link(fn ->
          # This root requires the supervisor to enforce its finite shutdown.
          Process.flag(:trap_exit, true)
          send(starter, {:demo_root_ready, self()})
          loop()
        end)

      receive do
        {:demo_root_ready, ^pid} -> {:ok, pid, :demo_start_info}
      after
        1_000 -> raise "Plugin root did not start"
      end
    end

    defp loop do
      receive do
        _message -> loop()
      end
    end
  end
end

defmodule AgentServer2Demo.LiveTurn do
  use Jido.Action, name: "server2_live_demo"

  def run(input, context) do
    runtime = context.plugin_inputs[AgentServer2Demo.LivePlugin].runtime
    true = Process.alive?(runtime.root)
    observer = runtime.observer

    directives =
      case input[:control] do
        :emit ->
          [
            %Jido.Agent.Directive.Emit{
              signal: Jido.Signal.new!("live", %{}, source: "/server2-demo")
            }
          ]

        :plugin ->
          [%AgentServer2Demo.PluginEffect{label: :demo}]

        :spawn ->
          [
            %Jido.Agent.Directive.SpawnProcess{
              child_spec:
                {Agent,
                 fn ->
                   send(observer, {:spawned_demo, self()})
                   :application_resource
                 end}
            }
          ]

        :stop ->
          [%Jido.Agent.Directive.Stop{reason: :demo_done}]

        _ ->
          []
      end

    {:ok, %{context.agent_state | count: context.agent_state.count + 1}, directives}
  end
end

defmodule AgentServer2Demo.Sink do
  use GenServer
  def init(observer), do: {:ok, observer}

  def handle_call({:signal, signal}, from, observer) do
    send(observer, {:effect_ready, signal.data.label, self(), from})
    {:noreply, observer}
  end

  def handle_info({:release, from}, observer) do
    GenServer.reply(from, :ok)
    {:noreply, observer}
  end
end

defmodule AgentServer2Demo.ActivationPlugin do
  use Jido.Plugin

  def child_spec(init) do
    width = init.options[:width] || 0

    if width == 0 do
      %{id: __MODULE__, start: {Agent, :start_link, [fn -> init.agent_server end]}}
    else
      children =
        for i <- 1..width do
          %{id: i, start: {Agent, :start_link, [fn -> init.agent_server end]}}
        end

      %{
        id: __MODULE__,
        start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]},
        type: :supervisor
      }
    end
  end
end

defmodule AgentServer2Demo.ActivationTurn do
  use Jido.Action, name: "activation_demo_turn"
  def run(_, context), do: {:ok, %{count: context.agent_state.count + 1}}
end

defmodule AgentServer2Demo do
  alias AgentServer2Demo.Counter
  alias Jido.AgentServer2, as: Server

  def run do
    {:ok, _} = Application.ensure_all_started(:jido)

    {:ok, demo_supervisor} =
      Supervisor.start_link([], strategy: :one_for_one, name: AgentServer2Demo.Supervisor)

    agent = Counter.instantiate!(id: "server2-demo")
    runner = AgentServer2Demo.Runner
    {:ok, runner_pid} = Runic.Runner.start_link(name: runner, store: Server.Store)
    {:ok, server} = start_server(agent: agent, runner: runner, max_postponed_signals: 1)

    try do
      IO.puts(
        "\nAgentServer2 demo: features 1–42, admission controls, stable Refs, and activation trees\n"
      )

      IO.puts("Checking startup options and failure handling...")
      check_startup_config(agent, runner)
      policy_demo(agent, runner)
      IO.puts("\nChecking Jido instance settings and ordered effects...")
      instance_effect_demo(agent)
      IO.puts("\nChecking Plugin readiness, admission, Emit, SpawnProcess, and Stop...")
      plugin_demo()
      IO.puts("\nChecking activation trees, recovery, child lifetimes, and adoption...")
      activation_demo()
      IO.puts("\nChecking required saves and restore into a new activation...")
      persistence_demo()
      IO.puts("\nChecking quiesce/resume, owners, touch, and idle stop...")
      control_demo(runner)
      IO.puts("\nChecking turns, queue limits, timeout, cancellation, and process cleanup...")
      {:ok, add_one} = Counter.add_signal(%{amount: 1})
      {:ok, add_two} = Counter.add_signal(%{amount: 2})
      check_invalid_signals(server, agent, add_one)
      {:ok, failure} = Counter.fail_signal(%{})
      {:error, _} = Server.call(server, failure)
      ^agent = Server.agent(server)
      %{state_version: 0} = Server.status(server)
      context = %{demo_pid: self(), tag: :request}

      # Submit returns immediately. The Action waits at the demo barrier.
      pending = Server.submit(server, add_one, context: context)
      {first_worker, first_id} = ready(:request)
      %{phase: :running, active: %{turn_id: ^first_id}} = Server.status(server)
      worker = Runic.Runner.lookup(runner, first_id)
      true = is_pid(worker)
      true = worker != first_worker
      IO.inspect(%{worker: worker, action: first_worker}, label: "Runner owns execution")
      IO.inspect(Server.status(server), label: "Running first turn")
      ^agent = Server.agent(server)
      %{state_version: 0} = Server.status(server)

      # A wait timeout keeps the pending result available for a later await.
      {:error, :timeout} = Server.await(pending, 0)

      # The Action monitors us, but our external requests remain valid.
      # Only one turn can wait. This turn must expire before it starts.
      expired =
        Server.submit(server, add_two, context: %{context | tag: :expired}, admission_timeout: 30)

      %{admission: %{postponed: 1, limit: 1}} = Server.status(server)
      {:error, {:overloaded, _}} = Server.call(server, add_two)
      rejected = Server.submit(server, add_two)
      {:error, {:overloaded, _}} = Server.await(rejected)
      :ok = Server.cast(server, add_two, context: %{context | tag: :dropped})
      IO.inspect(Server.status(server), label: "Queue full")

      # Wait for the admission budget, not for work completion.
      timer = :erlang.start_timer(40, self(), :admission_budget_elapsed)

      receive do
        {:timeout, ^timer, :admission_budget_elapsed} -> :ok
      after
        5_000 -> raise "Demo admission timer did not fire"
      end

      send(first_worker, :continue)
      {:ok, first, []} = Server.await(pending)
      1 = first.state.count
      nil = Runic.Runner.lookup(runner, first_id)
      {:error, :admission_timeout} = Server.await(expired)
      %{admission: %{postponed: 0}} = Server.status(server)

      # A cast runs after space is available. It has no result reply.
      :ok = Server.cast(server, add_two, context: %{context | tag: :cast})
      {second_worker, second_id} = ready(:cast)
      true = second_id != first_id

      %{active: %{turn_id: ^second_id, start_version: 1}, admission: %{postponed: 0}} =
        Server.status(server)

      send(second_worker, :continue)

      # This call waits behind the cast and acts as a completion barrier.
      missing = Jido.Signal.new!("demo.missing", %{}, source: "/server2-demo")
      {:error, _} = Server.call(server, missing, timeout: 5_000, context: nil)
      %{state: %{count: 3}} = Server.agent(server)
      %{state_version: 2} = Server.status(server)
      %{phase: :idle, active: nil, admission: %{postponed: 0}} = Server.status(server)

      # Owned Action work cannot synchronously call or await its own server.
      {:ok, probe} = Counter.probe_signal(%{})
      {:ok, _, []} = Server.call(server, probe, context: %{server: server})
      %{state: %{count: 3}} = saved = Server.agent(server)
      %{state_version: 3} = Server.status(server)
      clean(runner)

      # Both cancellation APIs wait for cleanup and preserve committed state.
      {:error, :not_running} = Server.cancel(server)
      cancelled = Server.submit(server, add_one, context: %{context | tag: :cancel})
      turn = watch(runner, ready(:cancel))
      :ok = Server.cancel(server)
      {:error, :cancelled} = Server.await(cancelled)
      stopped(runner, turn)
      ^saved = Server.agent(server)
      %{state_version: 3} = Server.status(server)
      clean(runner)

      cancelled = Server.submit(server, add_one, context: %{context | tag: :cancel_id})
      turn = watch(runner, ready(:cancel_id))
      {:error, :stale_turn} = Server.cancel_turn(server, first_id)
      :ok = Server.cancel_turn(server, turn.id)
      {:error, :cancelled} = Server.await(cancelled)
      stopped(runner, turn)
      ^saved = Server.agent(server)
      %{state_version: 3} = Server.status(server)
      clean(runner)

      # An old ID or late completion must not affect the next turn.
      pending = Server.submit(server, add_one, context: %{context | tag: :after_cancel})
      {action, _id} = ready(:after_cancel)
      {:error, :stale_turn} = Server.cancel_turn(server, turn.id)
      send(server, {:worker_complete, turn.id})
      send(server, {:turn_timeout, turn.id})
      send(action, :continue)
      {:ok, saved, []} = Server.await(pending)
      %{state: %{count: 4}} = saved
      %{state_version: 4} = status = Server.status(server)
      clean(runner)

      timeout_demo(agent, runner, add_one, add_two, context)
      abandon_demo(agent, runner, add_one, context)

      # Separate inspection reads; no combined atomic read is promised.
      IO.inspect(%{state: saved.state, state_version: status.state_version},
        label: "Final state and revision"
      )

      IO.puts(
        "PASS: invalid Signals/config/timers/Runner rejected, pending reply abandoned, safe Action failure, observed callers, owned-call rejection, timeout/cancellation cleanup, stale IDs/results ignored, queue replay, empty task pool/store, count=4, revision=4"
      )

      IO.puts("\nPASS: all AgentServer2 demo checks completed")
    after
      if Process.alive?(server), do: Server.stop(server, :normal)
      Supervisor.stop(runner_pid)
      Supervisor.stop(demo_supervisor)
    end
  end

  # OTP supervises roots. Every public request still addresses the worker.
  defp start_server(opts) do
    with {:ok, opts} <- Server.activation_options(opts) do
      spec = Supervisor.child_spec({Server, opts}, id: make_ref())

      case Supervisor.start_child(AgentServer2Demo.Supervisor, spec) do
        {:ok, root} -> {:ok, Server.Activation.worker(root)}
        error -> error
      end
    end
  end

  defp activation_demo do
    instance = AgentServer2Demo.ActivationJido
    {:ok, instance_pid} = Jido.start_link(name: instance, namespace: "jido/demo/agent-server2")

    definition = fn id, plugins ->
      Jido.Agent.define!(
        name: "activation_demo",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        plugins: plugins,
        routes: [{"activation.step", AgentServer2Demo.ActivationTurn}]
      )
      |> Jido.Agent.instantiate!(id: id)
    end

    plugin = fn width -> [{AgentServer2Demo.ActivationPlugin, width: width}] end
    signal = Jido.Signal.new!("activation.step", %{}, source: "/server2-demo")

    try do
      {:ok, parent} = Server.start(agent: definition.("activation-a", []), jido: instance)
      {:ok, b} = Server.spawn_child(parent, definition.("activation-b", plugin.(0)), :b)
      {:ok, c} = Server.spawn_child(parent, definition.("activation-c", plugin.(3)), :c)
      {:ok, nested} = Server.spawn_child(b, definition.("activation-nested", []), :nested)

      {:ok, independent} =
        Server.spawn_child(parent, definition.("activation-d", plugin.(2)), :d,
          placement: :independent,
          on_parent_exit: :continue
        )

      for server <- [parent, b, c, nested, independent], do: :ok = Server.await_ready(server)

      IO.inspect(
        %{
          activation: Server.activation(parent),
          worker: parent,
          children: Server.children(parent)
        },
        label: "Activation A"
      )

      owned = for server <- [b, c, nested], do: Server.activation(server)
      c_plugin = plugin_root(c)
      {_, leaf, _, _} = hd(Supervisor.which_children(c_plugin))
      generation = Server.status(c).generation
      Process.exit(leaf, :kill)

      wait(fn ->
        not Process.alive?(leaf) and
          Enum.all?(Supervisor.which_children(c_plugin), &(elem(&1, 1) != leaf))
      end)

      ^generation = Server.status(c).generation
      {:ok, b_ref} = Jido.agent_ref(instance, "activation-b")
      {:ok, committed_b, []} = Jido.call(instance, b_ref, signal)
      %{count: 1} = committed_b.state
      old_b_plugin = plugin_root(b)
      Process.exit(old_b_plugin, :kill)

      replacement =
        wait(fn ->
          case Server.whereis(instance, "activation-b") do
            pid when is_pid(pid) and pid != b -> pid
            _ -> nil
          end
        end)

      :ok = Server.await_ready(replacement)
      ^replacement = Server.children(parent).b.pid
      true = plugin_root(replacement) != old_b_plugin
      {:ok, ^replacement} = Jido.resolve_agent(instance, b_ref)
      ^committed_b = Jido.agent(instance, b_ref)
      1 = Jido.status(instance, b_ref).state_version
      pending = Jido.submit(instance, b_ref, signal)
      {:ok, %{state: %{count: 2}}, []} = Jido.await(pending)
      IO.inspect(Jido.agent(instance, b_ref), label: "Recovered B through its stable Ref")
      {:ok, %{state: %{count: 1}}, []} = Server.call(independent, signal)
      independent_root = Server.activation(independent)
      independent_plugin = plugin_root(independent)
      :ok = Server.stop(parent)
      for root <- owned, do: false = Process.alive?(root)
      wait(fn -> Server.status(independent).parent == nil end)
      true = Process.alive?(independent_plugin)
      {:ok, %{state: %{count: 2}}, []} = Server.call(independent, signal)
      {:ok, adopter} = Server.start(agent: definition.("activation-e", []), jido: instance)
      :ok = Server.adopt_child(adopter, independent, :adopted)
      ^independent = Server.children(adopter).adopted.pid
      monitor = Process.monitor(independent_root)
      :ok = Server.stop(adopter)

      receive do
        {:DOWN, ^monitor, :process, ^independent_root, _} -> :ok
      after
        1000 -> raise "Adopted activation did not stop"
      end

      false = Process.alive?(independent_plugin)
      [] = DynamicSupervisor.which_children(Jido.agent_supervisor_name(instance))
      clean(Jido.exec_runner_name(instance))

      IO.puts(
        "PASS: worker and Supervisor Plugins, local leaf recovery, fresh required-root generation, stable Ref routing, restored commit/revision, owned nested cleanup, independent survival, and adoption"
      )
    after
      Supervisor.stop(instance_pid)
    end
  end

  defp persistence_demo do
    instance = AgentServer2Demo.DurableJido
    table = :agent_server2_demo_durable
    adapter = {Jido.Persistence.ETS, table: table}

    {:ok, instance_pid} =
      Jido.start_link(name: instance, namespace: "jido/demo/durable", persistence: adapter)

    agent =
      Jido.Agent.define!(
        name: "durable_demo",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        plugins: [{AgentServer2Demo.ActivationPlugin, width: 3}],
        routes: [{"durable.step", AgentServer2Demo.ActivationTurn}]
      )
      |> Jido.Agent.instantiate!(id: "durable-agent")

    signal = Jido.Signal.new!("durable.step", %{}, source: "/server2-demo")

    try do
      # ETS survives these activations. It is a demo adapter, not disk storage.
      # Use a durable adapter to retain records across a BEAM restart.
      {:ok, first} =
        Server.start(
          agent: agent,
          jido: instance,
          persistence: :inherit,
          persistence_mode: :create,
          persistence_timeout: 5_000
        )

      :ok = Server.await_ready(first)
      old_root = Server.activation(first)
      old_plugin = plugin_root(first)
      {:ok, %{state: %{count: 1}}, []} = Server.call(first, signal)
      :ok = Server.stop(first)
      false = Process.alive?(old_root)
      false = Process.alive?(old_plugin)

      {:ok, restored} =
        Server.start(
          agent: agent,
          jido: instance,
          persistence: :inherit,
          persistence_mode: :restore
        )

      :ok = Server.await_ready(restored)
      true = Server.activation(restored) != old_root
      true = plugin_root(restored) != old_plugin
      %{count: 1} = Server.agent(restored).state
      1 = Server.status(restored).state_version
      {:ok, %{state: %{count: 2}}, []} = Server.call(restored, signal)

      {:ok, %{state: %{count: 2}}, 2} =
        Jido.Persistence.load_agent_with_revision(
          adapter,
          agent.module,
          agent.id,
          instance: instance
        )

      # Save the settled value again at revision 2, then confirm root cleanup.
      restored_root = Server.activation(restored)
      :ok = Server.hibernate(restored)
      false = Process.alive?(restored_root)
      clean(Jido.exec_runner_name(instance))

      IO.puts(
        "PASS: required revision writes, new activation restore, fresh Plugin tree, revision=2, and confirmed save-and-stop"
      )
    after
      Supervisor.stop(instance_pid)

      if :ets.whereis(:agent_server2_demo_durable_records) != :undefined,
        do: :ets.delete(:agent_server2_demo_durable_records)
    end
  end

  defp control_demo(runner) do
    agent =
      Jido.Agent.define!(
        name: "control_demo",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        routes: [{"control.step", AgentServer2Demo.ActivationTurn}]
      )
      |> Jido.Agent.instantiate!(id: "control-agent")

    signal = Jido.Signal.new!("control.step", %{}, source: "/server2-demo")
    {:ok, server} = start_server(agent: agent, runner: runner, idle_timeout: 1_000)
    root = Server.activation(server)
    :ok = Server.attach(server)
    :ok = Server.attach(server)
    [owner] = Server.status(server).owners
    true = owner == self()
    :ok = Server.quiesce(server)
    {:error, :quiesced} = Server.call(server, signal)
    ^agent = Server.agent(server)
    :quiesced = Server.status(server).admission.mode
    :ok = Server.touch(server)
    :ok = Server.resume(server)
    {:ok, %{state: %{count: 1}}, []} = Server.call(server, signal)
    {:error, %{reason: :persistence_not_configured, resumable?: true}} = Server.hibernate(server)
    :ok = Server.detach(server)
    :ok = Server.touch(server)
    monitor = Process.monitor(root)

    receive do
      {:DOWN, ^monitor, :process, ^root, _} -> :ok
    after
      3_000 -> raise "idle activation did not stop"
    end

    false = Process.alive?(server)
    clean(runner)

    IO.puts(
      "PASS: closed admission, readable Agent, explicit resume, idempotent owners, touch, and idle root cleanup"
    )
  end

  defp plugin_root(server) do
    {_, root, _, _} =
      List.keyfind(
        Supervisor.which_children(Server.activation(server)),
        {:plugin, AgentServer2Demo.ActivationPlugin},
        0
      )

    root
  end

  defp wait(fun), do: wait(fun, System.monotonic_time(:millisecond) + 5000)

  defp wait(fun, deadline) do
    case fun.() do
      value when value not in [nil, false] ->
        value

      _ ->
        if System.monotonic_time(:millisecond) >= deadline, do: raise("Demo state did not settle")

        receive do
        after
          1 -> wait(fun, deadline)
        end
    end
  end

  defp plugin_demo do
    instance = AgentServer2Demo.PluginJido
    observer = AgentServer2Demo.Observer
    Process.register(self(), observer)

    {:ok, instance_pid} =
      Jido.start_link(name: instance, agent_server2: [readiness_timeout: 2_000])

    agent =
      Jido.Agent.define!(
        name: "live_demo",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        plugins: [{AgentServer2Demo.LivePlugin, [observer: observer]}],
        routes: [{"live", AgentServer2Demo.LiveTurn}]
      )
      |> Jido.Agent.instantiate!(id: "live-demo")

    {:ok, server} = Server.start(agent: agent, jido: instance)
    signal = fn data -> Jido.Signal.new!("live", data, source: "/server2-demo") end

    try do
      {readiness_task, root} =
        receive do
          {:plugin_waiting, task, root} -> {task, root}
        after
          1_000 -> raise "Plugin did not reach readiness"
        end

      %{phase: :initializing, ready?: false} = Server.status(server)
      ^agent = Server.agent(server)
      {:error, :not_ready} = Server.call(server, signal.(%{}))
      nil = Server.whereis(instance, agent.id)
      send(readiness_task, :release)
      :ok = Server.await_ready(server)
      ^server = Server.whereis(instance, agent.id)
      {:ok, %{state: %{count: 1}}, [_]} = Server.call(server, signal.(%{control: :emit}))

      receive do
        {:plugin_admitted, 0} -> :ok
      after
        1_000 -> raise "Missing admission"
      end

      receive do
        {:plugin_admitted, 1} -> :ok
      after
        1_000 -> raise "Self-emission did not start"
      end

      {:ok, %{state: %{count: 3}}, [_]} = Server.call(server, signal.(%{control: :spawn}))

      child =
        receive do
          {:spawned_demo, child} -> child
        after
          1_000 -> raise "Process did not start"
        end

      true = Process.alive?(child)
      {:ok, %{state: %{count: 4}}, [_]} = Server.call(server, signal.(%{control: :plugin}))

      receive do
        {:plugin_committed, 4, 7} -> :ok
      after
        1_000 -> raise "Missing Plugin commit notification"
      end

      receive do
        {:plugin_effect, :demo, 4} -> :ok
      after
        1_000 -> raise "Missing Plugin directive dispatch"
      end

      ref = Process.monitor(server)
      root_ref = Process.monitor(root)
      {:ok, %{state: %{count: 5}}, [_]} = Server.call(server, signal.(%{control: :stop}))

      receive do
        {:DOWN, ^ref, :process, ^server, {:shutdown, :demo_done}} -> :ok
      after
        1_000 -> raise "Stop directive did not stop server"
      end

      receive do
        {:DOWN, ^root_ref, :process, ^root, _} -> :ok
      after
        1_000 -> raise "Plugin root did not stop"
      end

      true = Process.alive?(child)
      clean(Jido.exec_runner_name(instance))

      IO.puts(
        "PASS: OTP triple startup result, Plugin readiness/admission, commit hooks, Plugin directives, self-emission, supervised application process, and finite shutdown of a root that traps exits"
      )
    after
      if Process.alive?(server), do: Server.stop(server)
      Supervisor.stop(instance_pid)
      Process.unregister(observer)
    end
  end

  defp instance_effect_demo(agent) do
    instance = AgentServer2Demo.Jido

    {:ok, instance_pid} =
      Jido.start_link(
        name: instance,
        agent_server2: [turn_timeout: 100, directive_timeout: 1_000, debug: true]
      )

    {:ok, sink} = GenServer.start_link(AgentServer2Demo.Sink, self())
    {:ok, server} = Server.start(agent: agent, jido: instance, partition: "demo")

    try do
      ^server = Server.whereis(instance, agent.id, partition: "demo")
      ^server = Jido.whereis_agent(instance, agent.id, partition: "demo")
      true = Server.alive?(server)
      {:ok, signal} = Counter.effects_signal(%{})
      {:ok, %{state: %{count: 1}}, [_, _]} = Server.call(server, signal, context: %{sink: sink})
      first = effect_ready(1)

      %{active: %{stage: :effects, committed_version: 1}, effects: %{completed: 0, total: 2}} =
        Server.status(server)

      %{state: %{count: 1}} = Server.agent(server)
      {:error, :not_running} = Server.cancel(server)
      {:ok, probe} = Counter.probe_signal(%{})
      queued = Server.submit(server, probe, context: %{server: server})
      {:error, :timeout} = Server.await(queued, 0)
      send(sink, {:release, first})
      second = effect_ready(2)
      %{effects: %{completed: 1, total: 2}} = Server.status(server)
      send(sink, {:release, second})
      {:ok, _, []} = Server.await(queued)

      %{state_version: 2, last_effect_outcome: %{status: :succeeded, completed: 2}} =
        Server.status(server)

      clean(Jido.exec_runner_name(instance))
      Server.stop(server)
      nil = Server.whereis(instance, agent.id, partition: "demo")
      [] = DynamicSupervisor.which_children(Jido.agent_supervisor_name(instance))

      IO.puts(
        "PASS: instance lookup/defaults, commit reply, ordered owned effects, live reads, queued turn, and explicit stop"
      )
    after
      if Process.alive?(server), do: Server.stop(server, :normal)
      GenServer.stop(sink)
      Supervisor.stop(instance_pid)
    end
  end

  defp effect_ready(label) do
    receive do
      {:effect_ready, ^label, _sink, from} -> from
    after
      1_000 -> raise "Effect did not start"
    end
  end

  defp policy_demo(agent, runner) do
    {:ok, failure} = Counter.fail_signal(%{})
    {:ok, probe} = Counter.probe_signal(%{})

    {:ok, server} =
      start_server(
        agent: agent,
        runner: runner,
        exec_opts: [
          timeout: 1_000,
          max_attempts: 2,
          backoff: :linear,
          base_delay_ms: 10,
          max_delay_ms: 100
        ],
        error_policy: {:emit_signal, {:pid, target: self()}},
        error_policy_timeout: 1_000,
        debug: true,
        debug_max_events: 2
      )

    try do
      {:error, _} = Server.call(server, failure)

      receive do
        {:signal,
         %{type: "jido.agent_server2.error", data: %{status: :failed, committed?: false}}} ->
          :ok
      after
        1_000 -> raise "Error Signal did not arrive"
      end

      {:ok, _, []} = Server.call(server, probe, context: %{server: server})
      [%{status: :failed}, %{status: :succeeded}] = Server.history(server)
      %{error_count: 0, last_outcome: %{committed?: true}} = Server.status(server)
      IO.inspect(Server.history(server), label: "Bounded terminal history")
      clean(runner)

      IO.puts(
        "PASS: execution options, safe error Signal, terminal summaries, and bounded history"
      )
    after
      if Process.alive?(server), do: Server.stop(server, :normal)
    end
  end

  defp check_startup_config(agent, runner) do
    previous = Application.fetch_env(:jido, Server)

    try do
      for config <- [
            nil,
            %{turn_timeout: 60_000},
            [:invalid],
            [turn_timeout: -1],
            [turn_timout: 25],
            [turn_timeout: Integer.pow(10, 30)]
          ] do
        Application.put_env(:jido, Server, config)
        {:error, %{__struct__: _}} = start_server(agent: agent, runner: runner)

        # An explicit option does not read an unused application default.
        {:ok, server} =
          start_server(agent: agent, runner: runner, turn_timeout: :infinity)

        :ok = Server.stop(server, :normal)
      end
    after
      case previous do
        {:ok, config} -> Application.put_env(:jido, Server, config)
        :error -> Application.delete_env(:jido, Server)
      end
    end

    for timeout <- [4_294_967_296, Integer.pow(10, 30)] do
      {:error, %{__struct__: _}} =
        start_server(agent: agent, runner: runner, turn_timeout: timeout)
    end

    for key <- [:readiness_timeout, :commit_timeout, :directive_timeout] do
      {:error, error} = start_server([agent: agent, runner: runner] ++ [{key, :infinity}])
      true = String.contains?(Exception.message(error), Atom.to_string(key))
    end

    {:ok, not_runner} = Elixir.Agent.start_link(fn -> nil end, name: AgentServer2Demo.NotRunner)

    try do
      {:error, %{__struct__: _}} =
        start_server(
          agent: agent,
          runner: AgentServer2Demo.NotRunner,
          turn_timeout: :infinity
        )
    after
      Elixir.Agent.stop(not_runner)
    end

    reused = AgentServer2Demo.ReusedRunner
    {:ok, previous_runner} = Runic.Runner.start_link(name: reused, store: Server.Store)
    {Server.Store, nil} = Runic.Runner.get_store(reused)
    :ok = Supervisor.stop(previous_runner)
    {:ok, fake_runner} = Elixir.Agent.start_link(fn -> nil end, name: reused)

    try do
      {:error, %{__struct__: _}} = start_server(agent: agent, runner: reused)
    after
      Elixir.Agent.stop(fake_runner)
    end
  end

  defp check_invalid_signals(server, agent, signal) do
    for invalid <- [nil, %{type: "demo.add"}, %{signal | id: nil}, %{signal | type: nil}] do
      {:error, %{__struct__: _}} = Server.call(server, invalid)
      {:error, %{__struct__: _}} = Server.submit(server, invalid)
      {:error, %{__struct__: _}} = Server.cast(server, invalid)
    end

    for timeout <- [4_294_967_296, Integer.pow(10, 30)] do
      {:error, %{__struct__: _}} = Server.call(server, signal, timeout: timeout)
      {:error, %{__struct__: _}} = Server.submit(server, signal, admission_timeout: timeout)
      {:error, %{__struct__: _}} = Server.cancel(server, timeout)
    end

    ^agent = Server.agent(server)
    %{phase: :idle, state_version: 0} = Server.status(server)
  end

  defp abandon_demo(agent, runner, signal, context) do
    {:ok, server} = start_server(agent: agent, runner: runner)

    try do
      pending = Server.submit(server, signal, context: %{context | tag: :abandon})
      {action, _id} = ready(:abandon)
      {:error, :timeout} = Server.await(pending, 0)
      {:error, %{__struct__: _}} = Server.await(pending, 4_294_967_296)

      # A handle stays in its submitting process, including abandonment.
      task = Task.async(fn -> Server.abandon(pending) end)
      {:error, %{__struct__: _}} = Task.await(task)
      :ok = Server.abandon(pending)
      %{phase: :running} = Server.status(server)
      send(action, :continue)
      missing = Jido.Signal.new!("demo.missing", %{}, source: "/server2-demo")
      {:error, _} = Server.call(server, missing)
      %{state: %{count: 1}} = Server.agent(server)
      %{state_version: 1} = Server.status(server)
      request = pending.request_id
      {:monitors, monitors} = Process.info(self(), :monitors)
      false = Enum.member?(monitors, {:process, server})

      receive do
        {[:alias | ^request], _reply} -> raise "Abandoned reply reached the caller"
        {:DOWN, ^request, _, _, _} -> raise "Abandoned request monitor was retained"
      after
        0 -> :ok
      end

      # An already queued error reply can also be discarded.
      queued = Server.submit(server, missing)
      {:error, _} = Server.call(server, missing)
      :ok = Server.abandon(queued)
      queued_request = queued.request_id

      receive do
        {[:alias | ^queued_request], _reply} -> raise "Queued reply was not discarded"
      after
        0 -> :ok
      end

      clean(runner)
      IO.puts("PASS: abandoned reply released; turn still committed; no late reply or monitor")
    after
      if Process.alive?(server), do: Server.stop(server, :normal)
    end
  end

  defp timeout_demo(agent, runner, add_one, add_two, context) do
    {:ok, server} = start_server(agent: agent, runner: runner, turn_timeout: 250)

    try do
      timed = Server.submit(server, add_one, context: %{context | tag: :timeout})
      turn = watch(runner, ready(:timeout))
      queued = Server.submit(server, add_two, context: %{context | tag: :after_timeout})
      {:error, :turn_timeout} = Server.await(timed)
      stopped(runner, turn)
      {action, _id} = ready(:after_timeout)
      ^agent = Server.agent(server)
      %{state_version: 0} = Server.status(server)
      send(server, {:worker_complete, turn.id})
      send(server, {:turn_timeout, turn.id})
      {:error, :stale_turn} = Server.cancel_turn(server, turn.id)
      send(action, :continue)
      {:ok, %{state: %{count: 2}}, []} = Server.await(queued)
      %{phase: :idle, state_version: 1} = Server.status(server)
      clean(runner)
      IO.puts("PASS: timed-out work stopped before queued work; saved state preserved")
    after
      if Process.alive?(server), do: Server.stop(server, :normal)
    end
  end

  defp watch(runner, {action, id}) do
    worker = Runic.Runner.lookup(runner, id)
    true = is_pid(worker)

    %{
      id: id,
      action: action,
      action_ref: Process.monitor(action),
      worker: worker,
      worker_ref: Process.monitor(worker)
    }
  end

  defp stopped(runner, turn) do
    for {pid, ref} <- [{turn.action, turn.action_ref}, {turn.worker, turn.worker_ref}] do
      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        5_000 -> raise "Turn process did not stop"
      end
    end

    nil = Runic.Runner.lookup(runner, turn.id)
  end

  defp clean(runner) do
    [] = DynamicSupervisor.which_children(Module.concat(runner, WorkerSupervisor))
    [] = Task.Supervisor.children(Module.concat(runner, TaskSupervisor))
    {store, state} = Runic.Runner.get_store(runner)
    {:ok, []} = store.list(state)
  end

  defp ready(tag) do
    receive do
      {:turn_ready, worker, turn_id, ^tag} -> {worker, turn_id}
    after
      5_000 -> raise "Demo turn did not start: #{tag}"
    end
  end
end

AgentServer2Demo.run()
