defmodule JidoTest.AgentServer.HandoffTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.handoff", async: false
  @moduletag :tmp_dir

  import JidoTest.Eventually

  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.DurableTurn
  alias JidoTest.DurableFixtures.Probe

  defmodule EventLog do
    use GenServer

    def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)
    def record(event), do: GenServer.call(__MODULE__, {:record, event})
    def events, do: GenServer.call(__MODULE__, :events)
    def clear, do: GenServer.call(__MODULE__, :clear)

    @impl true
    def init(events), do: {:ok, events}

    @impl true
    def handle_call({:record, event}, _from, events), do: {:reply, :ok, [event | events]}
    def handle_call(:events, _from, events), do: {:reply, Enum.reverse(events), events}
    def handle_call(:clear, _from, _events), do: {:reply, :ok, []}
  end

  defmodule Effect do
    use Jido.Agent.Directive
    defstruct [:mode]
  end

  defmodule EffectRoot do
    use GenServer

    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    @impl true
    def init(init) do
      if init.options[:marker] == :changed do
        :ok = EventLog.record({:plugin_root_started, self(), init.options})
        :ok = Probe.gate({:handoff_reconcile, __MODULE__})
      end

      {:ok, init}
    end
  end

  defmodule EffectPlugin do
    use Jido.Plugin

    @impl true
    def directives(_opts), do: [Effect]

    @impl true
    def prepare(_preparation, _opts) do
      events = EventLog.events()

      cond do
        :reject_successor_prepare in events and :predecessor_prepare_seen in events ->
          {:error, :successor_prepare_rejected}

        :reject_successor_prepare in events ->
          :ok = EventLog.record(:predecessor_prepare_seen)
          {:ok, nil}

        true ->
          :ok = EventLog.record(:prepare)
          {:ok, nil}
      end
    end

    @impl true
    def admit(_root, admission, _opts) do
      :ok = EventLog.record({:admit, admission.state_version})
      {:ok, nil}
    end

    @impl true
    def after_commit(_root, commit, _opts) do
      :ok = EventLog.record({:after_commit, commit.state_version})
      :ok
    end

    @impl true
    def dispatch(_runtime, %Effect{mode: :notify}, context, _opts) do
      :ok = EventLog.record({:effect, context.state_version})
      send(context.turn_context.observer, :predecessor_effect)
      :ok
    end

    def dispatch(_runtime, %Effect{mode: :block}, _context, _opts),
      do: JidoTest.DurableFixtures.Probe.gate({:handoff_effect, __MODULE__})

    def dispatch(_runtime, %Effect{mode: :fail}, _context, _opts),
      do: {:error, :controlled_effect_failure}

    @impl true
    def quiesce(_runtime, _opts), do: :ok

    @impl true
    def resume(_runtime, _opts), do: :ok

    @impl true
    def child_spec(init), do: %{id: __MODULE__, start: {EffectRoot, :start_link, [init]}}
  end

  defmodule EffectOnlyPlugin do
    use Jido.Plugin

    @impl true
    def directives(_opts), do: [Effect]

    @impl true
    def dispatch(_runtime, %Effect{mode: :block}, _context, _opts),
      do: Probe.gate({:handoff_effect, __MODULE__})
  end

  defmodule Successor do
    use Jido.Action,
      name: "agent_server_handoff_successor",
      schema: Zoi.object(%{count: Zoi.integer()})

    def run(input, context) do
      if observer = context[:observer], do: send(observer, :successor_started)
      {:ok, %{count: input.count + 1}}
    end
  end

  defmodule BlockingSuccessor do
    use Jido.Action,
      name: "agent_server_blocking_handoff_successor",
      schema: Zoi.object(%{count: Zoi.integer()})

    def run(input, _context) do
      :ok = Probe.gate({:handoff_successor, __MODULE__})
      :ok = EventLog.record(:blocking_successor_started)
      {:ok, %{count: input.count + 1}}
    end
  end

  defmodule ErrorSuccessor do
    use Jido.Action,
      name: "agent_server_error_handoff_successor",
      schema: Zoi.object(%{count: Zoi.integer()})

    def run(_input, _context), do: {:error, :successor_failed}
  end

  defmodule InvalidSuccessor do
    use Jido.Action,
      name: "agent_server_invalid_handoff_successor",
      schema: Zoi.object(%{count: Zoi.integer()}),
      output_schema: Zoi.object(%{count: Zoi.integer()})

    def run(_input, _context), do: {:ok, %{count: "invalid"}}
  end

  defmodule FlowErrorStep do
    use Jido.Action,
      name: "agent_server_error_handoff_flow_step",
      schema: Zoi.object(%{count: Zoi.integer()})

    def run(_input, _context), do: {:error, :successor_flow_failed}
  end

  defmodule ErrorSuccessorFlow do
    use Jido.Flow, name: "agent_server_error_handoff_successor_flow"

    flow do
      step "fail", action: FlowErrorStep, params: %{count: input(:count)}
      output result("fail")
    end
  end

  defmodule Select do
    use Jido.Action, name: "agent_server_handoff_select"
    def run(input, _context), do: {:handoff, input, Successor}
  end

  defmodule Before do
    use Jido.Action, name: "agent_server_handoff_before"

    def run(input, _context) do
      {:ok, %{count: input.count}, [%Effect{mode: input.effect_mode}]}
    end
  end

  defmodule BeforeReply do
    use Jido.Action, name: "agent_server_handoff_before_reply"

    def run(input, context) do
      output = Jido.Signal.new!("handoff.reply", %{count: input.count}, source: "/agent/handoff")
      {:ok, output} = Jido.Signal.put_context(output, "jidocausationid", context.signal.id)
      send(context.observer, {:handoff_reply, output})

      {:ok, %{count: input.count}, [Jido.Agent.Directive.reply(output)]}
    end
  end

  defmodule BeforePluginChange do
    use Jido.Action, name: "agent_server_handoff_before_plugin_change"

    def run(input, context) do
      output = Jido.Signal.new!("handoff.plugin_reply", %{count: input.count}, source: "/agent")
      {:ok, output} = Jido.Signal.put_context(output, "jidocausationid", context.signal.id)
      send(context.observer, {:plugin_reply, output})

      {:ok, %{count: input.count},
       [
         Jido.Agent.Directive.plugin_configure(EffectPlugin, marker: :changed),
         Jido.Agent.Directive.reply(output)
       ]}
    end
  end

  defmodule Increment do
    use Jido.Action, name: "agent_server_handoff_increment"

    def run(_input, context),
      do: {:ok, %{context.agent_state | count: context.agent_state.count + 1}}
  end

  defmodule SelectBlocking do
    use Jido.Action, name: "agent_server_blocking_handoff_select"
    def run(input, _context), do: {:handoff, input, BlockingSuccessor}
  end

  defmodule BlockingSuccessorFlow do
    use Jido.Flow, name: "agent_server_blocking_handoff_successor_flow"

    flow do
      step "block", action: BlockingSuccessor, params: %{count: input(:count)}
      output result("block")
    end
  end

  defmodule SelectBlockingFlow do
    use Jido.Action, name: "agent_server_blocking_flow_handoff_select"
    def run(input, _context), do: {:handoff, input, BlockingSuccessorFlow}
  end

  defmodule SelectError do
    use Jido.Action, name: "agent_server_error_handoff_select"
    def run(input, _context), do: {:handoff, input, ErrorSuccessor}
  end

  defmodule SelectInvalid do
    use Jido.Action, name: "agent_server_invalid_handoff_select"
    def run(input, _context), do: {:handoff, input, InvalidSuccessor}
  end

  defmodule SelectErrorFlow do
    use Jido.Action, name: "agent_server_error_flow_handoff_select"
    def run(input, _context), do: {:handoff, input, ErrorSuccessorFlow}
  end

  defmodule Flow do
    use Jido.Flow, name: "agent_server_handoff_flow"

    flow do
      handoff "next", selector: Select, params: %{count: input(:count)}
      output result("next")
    end
  end

  defmodule EffectsFlow do
    use Jido.Flow, name: "agent_server_effects_handoff_flow"

    flow do
      step "before",
        action: Before,
        params: %{count: input(:count), effect_mode: :notify}

      handoff "next", selector: Select, params: result("before")
      output result("next")
    end
  end

  defmodule EffectsBlockingFlow do
    use Jido.Flow, name: "agent_server_effects_blocking_handoff_flow"

    flow do
      step "before",
        action: Before,
        params: %{count: input(:count), effect_mode: :block}

      handoff "next", selector: SelectBlocking, params: result("before")
      output result("next")
    end
  end

  defmodule ReplyFlow do
    use Jido.Flow, name: "agent_server_reply_handoff_flow"

    flow do
      step "before", action: BeforeReply, params: %{count: input(:count)}
      handoff "next", selector: Select, params: result("before")
      output result("next")
    end
  end

  defmodule PluginChangeFlow do
    use Jido.Flow, name: "agent_server_plugin_change_handoff_flow"

    flow do
      step "before", action: BeforePluginChange, params: %{count: input(:count)}
      handoff "next", selector: SelectBlocking, params: result("before")
      output result("next")
    end
  end

  defmodule EffectsFailingFlow do
    use Jido.Flow, name: "agent_server_effects_failing_handoff_flow"

    flow do
      step "before",
        action: Before,
        params: %{count: input(:count), effect_mode: :fail}

      handoff "next", selector: Select, params: result("before")
      output result("next")
    end
  end

  defmodule ErrorHandoffFlow do
    use Jido.Flow, name: "agent_server_error_handoff_flow"

    flow do
      handoff "next", selector: SelectError, params: %{count: input(:count)}
      output result("next")
    end
  end

  defmodule InvalidHandoffFlow do
    use Jido.Flow, name: "agent_server_invalid_handoff_flow"

    flow do
      handoff "next", selector: SelectInvalid, params: %{count: input(:count)}
      output result("next")
    end
  end

  defmodule ErrorFlowHandoffFlow do
    use Jido.Flow, name: "agent_server_error_flow_handoff_flow"

    flow do
      handoff "next", selector: SelectErrorFlow, params: %{count: input(:count)}
      output result("next")
    end
  end

  defmodule TerminalStorage do
    @behaviour Jido.Persistence.Adapter

    def get(key, opts), do: Jido.Persistence.File.get(key, opts)

    def compare_and_swap(key, expected, value, opts) do
      record = :erlang.binary_to_term(value, [:safe])

      with :ok <- Jido.Persistence.File.compare_and_swap(key, expected, value, opts) do
        case record do
          %{server_turn: %{status: :failed}} ->
            Probe.gate({:handoff_terminal_write, Map.get(record, :agent_module)})

          %{server_turn: %{status: :released}} ->
            Probe.gate({:handoff_release_write, Map.get(record, :agent_module)})

          _ ->
            :ok
        end
      end
    end
  end

  defmodule MiddleFlow do
    use Jido.Flow, name: "agent_server_middle_handoff_flow"

    flow do
      handoff "next", selector: Select, params: %{count: input(:count)}
      output result("next")
    end
  end

  defmodule SelectMiddle do
    use Jido.Action, name: "agent_server_middle_handoff_select"
    def run(input, _context), do: {:handoff, input, MiddleFlow}
  end

  defmodule ChainFlow do
    use Jido.Flow, name: "agent_server_chained_handoff_flow"

    flow do
      handoff "next", selector: SelectMiddle, params: %{count: input(:count)}
      output result("next")
    end
  end

  defmodule BlockingFlow do
    use Jido.Flow, name: "agent_server_blocking_handoff_flow"

    flow do
      handoff "next", selector: SelectBlocking, params: %{count: input(:count)}
      output result("next")
    end
  end

  defmodule BlockingFlowSuccessorHandoff do
    use Jido.Flow, name: "agent_server_blocking_flow_successor_handoff"

    flow do
      handoff "next", selector: SelectBlockingFlow, params: %{count: input(:count)}
      output result("next")
    end
  end

  defmodule Agent do
    use Jido.Agent, name: "agent_server_handoff_agent"

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    plugins do
      plugin EffectPlugin
    end

    routes do
      route "handoff", Flow
      route "effects_handoff", EffectsFlow
      route "effects_blocking_handoff", EffectsBlockingFlow
      route "effects_failing_handoff", EffectsFailingFlow
      route "reply_handoff", ReplyFlow
      route "plugin_change_handoff", PluginChangeFlow
      route "chain_handoff", ChainFlow
      route "blocking_handoff", BlockingFlow
      route "blocking_flow_handoff", BlockingFlowSuccessorHandoff
      route "increment", Increment
      route "error_handoff", ErrorHandoffFlow
      route "invalid_handoff", InvalidHandoffFlow
      route "error_flow_handoff", ErrorFlowHandoffFlow
    end
  end

  defmodule PlainAgent do
    use Jido.Agent, name: "agent_server_plain_handoff_agent"

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    plugins do
      plugin EffectOnlyPlugin
    end

    routes do
      route "handoff", Flow
      route "effects_blocking_handoff", EffectsBlockingFlow
    end
  end

  setup do
    start_supervised!({Probe, self()})
    start_supervised!(EventLog)
    :ok
  end

  defp start(c, opts) do
    start(c, Agent, opts)
  end

  defp start(c, agent, opts) do
    {:ok, server} =
      Jido.start_agent(
        c.jido,
        agent,
        Keyword.merge([id: unique_id("handoff")], opts)
      )

    assert :ok = Server.await_ready(server)
    server
  end

  defp persisted_turn(c, id, adapter \\ nil) do
    adapter = adapter || {Jido.Persistence.File, path: c.tmp_dir}

    assert {:ok, _agent, _revision, turn} =
             Jido.Persistence.load_agent_with_server_turn(adapter, Agent, id, instance: c.jido)

    turn
  end

  defp active_handoff_ids(server) do
    {_phase, data} = :sys.get_state(server)
    {data.active.turn_id, data.active.handoff_receipt.id}
  end

  defp cancel_handoff(server, :active, _predecessor_id, _successor_id),
    do: Server.cancel(server)

  defp cancel_handoff(server, :predecessor, predecessor_id, _successor_id),
    do: Server.cancel_turn(server, predecessor_id)

  defp cancel_handoff(server, :successor, _predecessor_id, successor_id),
    do: Server.cancel_turn(server, successor_id)

  defp install_handoff_pending_barrier(server) do
    observer = self()

    debug = fn
      :armed, {:consume, _event, _state, :handoff_pending}, _process_state ->
        receive do
          {:handoff_successor, successor_id} ->
            send(observer, {:handoff_pending_barrier, self(), successor_id})

            receive do
              :release_handoff_pending -> :done
            end
        end

      state, _event, _process_state ->
        state
    end

    :sys.install(server, {debug, :armed})
  end

  @tag obligation: "jido.agent_server.handoff.I1"
  test "Handoff runs the successor as a new Turn and returns only its result", c do
    server = start(c, debug: true)

    pending = Server.submit(server, signal("handoff", %{count: 4}))
    assert {:ok, agent, []} = Server.await(pending, 500)
    assert agent.state == %{count: 5}

    [predecessor, successor] = Server.history(server)
    assert predecessor.status == :succeeded
    assert successor.status == :succeeded
    assert predecessor.turn_id != successor.turn_id
    assert Server.status(server).durable_turn == nil

    assert {:ok, _, []} = Server.call(server, signal("increment", %{}))
    ordinary = Server.history(server) |> List.last()
    refute Map.has_key?(ordinary, :chain_id)
    refute Map.has_key?(ordinary, :chain_order)
  end

  @tag obligation: "jido.agent_server.handoff.I1"
  test "a Handoff without hooks or Directives takes the direct terminal path", c do
    server = start(c, PlainAgent, debug: true)

    assert {:ok, %{state: %{count: 5}}, []} =
             Server.call(server, signal("handoff", %{count: 4}))

    assert Enum.map(Server.history(server), & &1.status) == [:succeeded, :succeeded]
  end

  @tag obligation: "jido.agent_server.handoff.I2"
  test "a durable Handoff saves chain identity through successor completion", c do
    server =
      start(c,
        debug: true,
        persistence: {Jido.Persistence.File, path: c.tmp_dir}
      )

    assert {:ok, agent, []} = Server.call(server, signal("handoff", %{count: 8}))
    assert agent.state == %{count: 9}

    assert %{
             status: :completed,
             chain_id: chain_id,
             chain_order: 1,
             id: successor_id
           } = Server.status(server).durable_turn

    assert is_binary(chain_id)
    assert successor_id != chain_id

    [predecessor, successor] = Server.history(server)
    assert predecessor.turn_id == chain_id
    assert successor.turn_id == successor_id
    assert predecessor.chain_id == chain_id
    assert successor.chain_id == chain_id
    assert [predecessor.chain_order, successor.chain_order] == [0, 1]
  end

  @tag obligation: "jido.agent_server.handoff.I2"
  test "a released Handoff rejects a changed execution fingerprint" do
    signal = Jido.Signal.new!("handoff.test", %{count: 1}, source: "/test")
    agent = Agent.instantiate!(id: "handoff-fingerprint")
    instruction = Jido.Instruction.new!(target: Successor, params: %{count: 1})

    data = %{
      active: %{
        handoff_id: "successor",
        source_signal: signal,
        turn_context: %{},
        chain_id: "chain",
        chain_order: 0,
        turn_id: "predecessor"
      },
      persistence: false
    }

    assert {:ok, accepted} = DurableTurn.accept_handoff(data, instruction)

    released =
      Map.merge(accepted, %{
        status: :released,
        admitted_signal: signal,
        plugin_inputs: %{},
        expires_at: :infinity
      })

    assert {:ok, _prepared} = DurableTurn.restore_handoff(agent, released, %{}, [])

    assert {:error, :execution_definition_changed} =
             DurableTurn.restore_handoff(
               agent,
               %{released | fingerprint: "changed"},
               %{},
               []
             )
  end

  @tag obligation: "jido.agent_server.handoff.I1"
  test "predecessor Directives finish before the successor starts", c do
    :ok = EventLog.clear()
    server = start(c, [])

    assert {:ok, %{state: %{count: 3}}, []} =
             Server.call(
               server,
               signal("effects_handoff", %{count: 2}),
               context: %{observer: self()}
             )

    assert_receive :predecessor_effect
    assert_receive :successor_started

    assert [
             :prepare,
             {:admit, 0},
             {:after_commit, 1},
             {:effect, 1},
             :prepare,
             {:admit, 1}
             | _rest
           ] = EventLog.events()
  end

  @tag obligation: "jido.agent_server.handoff.I1"
  test "Plugin reconciliation finishes before the successor result", c do
    :ok = EventLog.clear()
    :ok = Probe.configure(:handoff_reconcile)
    server = start(c, turn_timeout: :infinity)
    {_phase, before} = :sys.get_state(server)
    old_root = Map.fetch!(before.plugin_refs, EffectPlugin)

    pending =
      Server.submit(server, signal("plugin_change_handoff", %{count: 2}),
        context: %{observer: self()}
      )

    assert_receive {:plugin_reply, output}, 1_000
    output_id = output.id
    refute_received %Jido.Signal{id: ^output_id}

    assert_receive {:durable_barrier, :handoff_reconcile, _reconciler}, 5_000
    assert {:effects, %{active: %{reconciling: true}}} = :sys.get_state(server)
    assert {:error, :timeout} = Server.await(pending, 0)

    :ok = Probe.configure(:handoff_successor)
    :ok = Probe.release()
    assert_receive {:durable_barrier, :handoff_successor, _successor}, 5_000

    assert {:error, :timeout} = Server.await(pending, 0)

    assert Keyword.fetch!(Jido.Agent.runtime_plugins(Server.agent(server)), EffectPlugin) ==
             [marker: :changed]

    {_phase, after_reconciliation} = :sys.get_state(server)
    new_root = Map.fetch!(after_reconciliation.plugin_refs, EffectPlugin)
    assert is_pid(new_root)
    assert new_root != old_root

    assert [:prepare, {:admit, 0} | _] = EventLog.events()

    :ok = Probe.release()
    assert {:ok, %{state: %{count: 3}}, []} = Server.await(pending, 500)
    assert_receive %Jido.Signal{id: ^output_id}, 500
    assert :prepare in EventLog.events()
    assert {:admit, 1} in EventLog.events()
    refute {:after_commit, 1} in EventLog.events()
    assert_eventually({:after_commit, 2} in EventLog.events())
  end

  @tag obligation: "jido.agent_server.handoff.I1"
  test "a Handoff without commit hooks uses the Directive timeout", c do
    :ok = Probe.configure(:handoff_effect)

    server =
      start(c, PlainAgent,
        directive_timeout: 40,
        commit_timeout: 1_000,
        turn_timeout: :infinity
      )

    pending = Server.submit(server, signal("effects_blocking_handoff", %{count: 2}))
    assert_receive {:durable_barrier, :handoff_effect, _effect}, 500
    assert {:error, reason} = Server.await(pending, 500)
    refute reason == :timeout
    refute_received :successor_started
    assert Process.alive?(server)
  end

  @tag obligation: "jido.agent_server.handoff.I1"
  test "the handoff pending state keeps postponed work behind the successor", c do
    :ok = Probe.configure(:handoff_effect)
    server = start(c, turn_timeout: :infinity)

    handoff = Server.submit(server, signal("effects_blocking_handoff", %{count: 2}))
    assert_receive {:durable_barrier, :handoff_effect, effect_task}, 5_000

    queued = Server.submit(server, signal("increment", %{}))
    assert Server.status(server).admission.postponed == 1

    :ok = install_handoff_pending_barrier(server)
    :ok = Probe.configure(:handoff_successor)
    :ok = Probe.release()
    assert_receive {:handoff_pending_barrier, ^server, successor_id}, 5_000
    refute Process.alive?(effect_task)

    status = Task.async(fn -> Server.status(server) end)
    assert Task.yield(status, 0) == nil
    send(server, :release_handoff_pending)

    assert %{phase: :handoff_pending, active: nil} = Task.await(status)
    send(server, {:handoff_successor, successor_id})
    assert_receive {:durable_barrier, :handoff_successor, _successor}, 5_000
    :ok = Probe.release()
    assert {:ok, %{state: %{count: 3}}, []} = Server.await(handoff)
    assert {:ok, %{state: %{count: 4}}, []} = Server.await(queued)
  end

  @tag obligation: "jido.agent_server.handoff.I2"
  test "chained Handoffs retain one chain and increase chain order", c do
    server =
      start(c,
        debug: true,
        persistence: {Jido.Persistence.File, path: c.tmp_dir}
      )

    assert {:ok, %{state: %{count: 6}}, []} =
             Server.call(server, signal("chain_handoff", %{count: 5}))

    assert %{status: :completed, chain_order: 2, chain_id: chain_id, id: successor_id} =
             Server.status(server).durable_turn

    [predecessor, middle, successor] = Server.history(server)
    assert chain_id == predecessor.turn_id
    assert middle.turn_id != predecessor.turn_id
    assert successor.turn_id == successor_id
    assert Enum.all?([predecessor, middle, successor], &(&1.chain_id == chain_id))
    assert Enum.map([predecessor, middle, successor], & &1.chain_order) == [0, 1, 2]
  end

  @tag obligation: "jido.agent_server.handoff.I2"
  test "cancellation after acceptance accepts every chain selector", c do
    for selector <- [:active, :predecessor, :successor] do
      :ok = Probe.configure(:handoff_effect)

      server =
        start(c,
          persistence: {Jido.Persistence.File, path: c.tmp_dir}
        )

      pending = Server.submit(server, signal("effects_blocking_handoff", %{count: 1}))
      assert_receive {:durable_barrier, :handoff_effect, _effect_task}, 5_000
      {predecessor_id, successor_id} = active_handoff_ids(server)
      assert Server.status(server).durable_turn.status == :accepted
      assert {:error, :stale_turn} = Server.cancel_turn(server, "stale")

      assert :ok = cancel_handoff(server, selector, predecessor_id, successor_id)
      assert {:error, :cancelled} = Server.await(pending)
      assert Server.status(server).durable_turn.status == :cancelled
      refute_received {:durable_barrier, :handoff_successor, _}
      :ok = Server.stop(server)
    end
  end

  @tag obligation: "jido.agent_server.handoff.I1"
  test "cancellation in handoff pending accepts every chain selector", c do
    for selector <- [:active, :predecessor, :successor] do
      :ok = Probe.configure(:handoff_effect)
      server = start(c, turn_timeout: :infinity)
      pending = Server.submit(server, signal("effects_blocking_handoff", %{count: 2}))
      assert_receive {:durable_barrier, :handoff_effect, _effect_task}, 5_000
      {predecessor_id, successor_id} = active_handoff_ids(server)
      :ok = install_handoff_pending_barrier(server)

      :ok = Probe.release()
      assert_receive {:handoff_pending_barrier, ^server, ^successor_id}, 5_000

      cancellation =
        Task.async(fn -> cancel_handoff(server, selector, predecessor_id, successor_id) end)

      assert Task.yield(cancellation, 0) == nil
      send(server, :release_handoff_pending)

      assert :ok = Task.await(cancellation)
      assert {:error, :cancelled} = Server.await(pending)
      assert Process.alive?(server)
      :ok = Server.stop(server)
    end
  end

  @tag obligation: "jido.agent_server.handoff.I1"
  test "quiesce does not treat a pending Handoff as settled", c do
    :ok = Probe.configure(:handoff_effect)
    server = start(c, turn_timeout: :infinity)
    pending = Server.submit(server, signal("effects_blocking_handoff", %{count: 2}))
    assert_receive {:durable_barrier, :handoff_effect, _effect_task}, 5_000
    :ok = install_handoff_pending_barrier(server)

    :ok = Probe.release()
    assert_receive {:handoff_pending_barrier, ^server, successor_id}, 5_000

    send(server, {:handoff_successor, "stale"})
    stale = Task.async(fn -> Server.cancel_turn(server, "stale") end)

    control = Task.async(fn -> Server.quiesce(server, timeout: 80) end)
    assert Task.yield(control, 0) == nil
    send(server, :release_handoff_pending)

    assert {:error, :stale_turn} = Task.await(stale)
    assert {:error, :quiesce_timeout} = Task.await(control, 1_000)
    assert Server.status(server).phase == :handoff_pending
    send(server, {:handoff_successor, successor_id})
    assert :ok = Server.cancel(server)
    assert {:error, :cancelled} = Server.await(pending)
    eventually(fn -> Server.status(server).admission.mode == :quiesced end)
  end

  @tag obligation: "jido.agent_server.handoff.I2"
  test "recovery fails an accepted but unreleased successor without replay", c do
    :ok = Probe.configure(:handoff_effect)

    server =
      start(c,
        persistence: {Jido.Persistence.File, path: c.tmp_dir}
      )

    id = Server.agent(server).id
    pending = Server.submit(server, signal("effects_blocking_handoff", %{count: 12}))
    assert_receive {:durable_barrier, :handoff_effect, effect}, 5_000
    assert Server.status(server).durable_turn.status == :accepted

    assert persisted_turn(c, id) |> Map.keys() |> Enum.sort() ==
             Enum.sort([
               :id,
               :status,
               :signal,
               :context,
               :fingerprint,
               :instruction,
               :chain_id,
               :chain_order,
               :predecessor_id
             ])

    monitor = Process.monitor(server)
    effect_monitor = Process.monitor(effect)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^server, :killed}, 5_000
    assert_receive {:DOWN, ^effect_monitor, :process, ^effect, _}, 5_000

    restored =
      eventually(fn ->
        case Jido.whereis_agent(c.jido, id) do
          pid when is_pid(pid) and pid != server -> pid
          _ -> nil
        end
      end)

    assert :ok = Server.await_ready(restored)
    assert Server.agent(restored).state == %{count: 0}
    assert Server.status(restored).durable_turn.status == :failed

    assert {:ok, _agent, 3, %{status: :failed}} =
             Jido.Persistence.load_agent_with_server_turn(
               {Jido.Persistence.File, path: c.tmp_dir},
               Agent,
               id,
               instance: c.jido
             )

    assert Server.status(restored).state_version == 3
    assert {:error, _} = Server.await(pending)
  end

  @tag obligation: "jido.agent_server.handoff.I2"
  test "recovery resumes released Action and Flow successors", c do
    for type <- ["blocking_handoff", "blocking_flow_handoff"] do
      :ok = Probe.configure(:handoff_successor)

      server =
        start(c,
          persistence: {Jido.Persistence.File, path: c.tmp_dir}
        )

      id = Server.agent(server).id
      pending = Server.submit(server, signal(type, %{count: 12}))
      assert_receive {:durable_barrier, :handoff_successor, action}, 5_000
      first_status = Server.status(server).durable_turn
      assert first_status.status == :released

      assert persisted_turn(c, id) |> Map.keys() |> Enum.sort() ==
               Enum.sort([
                 :id,
                 :status,
                 :signal,
                 :admitted_signal,
                 :context,
                 :plugin_inputs,
                 :fingerprint,
                 :expires_at,
                 :instruction,
                 :chain_id,
                 :chain_order,
                 :predecessor_id
               ])

      monitor = Process.monitor(server)
      action_monitor = Process.monitor(action)
      Process.exit(server, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^server, :killed}, 5_000
      assert_receive {:DOWN, ^action_monitor, :process, ^action, _}, 5_000

      restored =
        eventually(fn ->
          case Jido.whereis_agent(c.jido, id) do
            pid when is_pid(pid) and pid != server -> pid
            _ -> nil
          end
        end)

      assert :ok = Server.await_ready(restored)
      eventually(fn -> Server.agent(restored).state == %{count: 13} end)
      assert Server.status(restored).durable_turn.status == :completed
      assert Server.status(restored).durable_turn.id == first_status.id
      assert {:error, _} = Server.await(pending)
      :ok = Server.stop(restored)
    end
  end

  @tag obligation: "jido.agent_server.handoff.I2"
  test "released recovery keeps the saved absolute successor expiry", c do
    id = unique_id("expired-handoff")
    adapter = {Jido.Persistence.File, path: c.tmp_dir}
    agent = Agent.instantiate!(id: id)
    source = signal("blocking_handoff", %{count: 2})
    instruction = Jido.Instruction.new!(target: BlockingSuccessor, params: %{count: 2})

    data = %{
      active: %{
        handoff_id: "successor",
        source_signal: source,
        turn_context: %{},
        chain_id: "predecessor",
        chain_order: 0,
        turn_id: "predecessor"
      },
      persistence: adapter
    }

    assert {:ok, accepted} = DurableTurn.accept_handoff(data, instruction)

    released =
      Map.merge(accepted, %{
        status: :released,
        admitted_signal: source,
        plugin_inputs: %{},
        expires_at: System.system_time(:millisecond) - 1
      })

    assert :ok =
             Jido.Persistence.save_agent(adapter, agent,
               instance: c.jido,
               server_turn: released
             )

    :ok = Probe.configure(:handoff_successor)

    {:ok, server} =
      Jido.start_agent(c.jido, Agent,
        id: id,
        persistence: adapter,
        persistence_mode: :restore,
        turn_timeout: :infinity
      )

    assert :ok = Server.await_ready(server)
    eventually(fn -> Server.status(server).durable_turn.status == :failed end)
    refute_received {:durable_barrier, :handoff_successor, _}
    assert Server.agent(server).state == %{count: 0}
  end

  @tag obligation: "jido.agent_server.handoff.I1"
  test "transient successor failures keep the server alive", c do
    server = start(c, [])

    for type <- ["error_handoff", "invalid_handoff", "error_flow_handoff"] do
      assert {:error, _} = Server.call(server, signal(type, %{count: 2}))
      assert Process.alive?(server)
    end

    assert {:ok, %{state: %{count: 3}}, []} =
             Server.call(server, signal("handoff", %{count: 2}))
  end

  @tag obligation: "jido.agent_server.handoff.I1"
  test "successor preparation failure closes the Handoff without starting it", c do
    server = start(c, [])
    :ok = EventLog.record(:reject_successor_prepare)
    pending = Server.submit(server, signal("handoff", %{count: 2}))

    assert {:error, _reason} = Server.await(pending, 500)
    refute_received :successor_started
    assert Process.alive?(server)
    assert Server.status(server).durable_turn == nil
  end

  @tag obligation: "jido.agent_server.handoff.I2"
  test "a non-portable durable source context is rejected before execution", c do
    server =
      start(c,
        persistence: {Jido.Persistence.File, path: c.tmp_dir}
      )

    pending =
      Server.submit(server, signal("handoff", %{count: 2}), context: %{local: self()})

    assert {:error, reason} = Server.await(pending, 500)
    refute reason == :timeout
    assert Process.alive?(server)
    refute_received :successor_started
  end

  @tag obligation: "jido.agent_server.handoff.I1"
  test "nil persistence keeps local Handoff input transient", c do
    server = start(c, persistence: nil)

    assert {:ok, %{state: %{count: 3}}, []} =
             Server.call(server, signal("handoff", %{count: 2, local: self()}))

    assert Server.status(server).durable_turn == nil
  end

  @tag obligation: "jido.agent_server.handoff.I1"
  test "running successor cancellation accepts every chain selector", c do
    for selector <- [:active, :predecessor, :successor] do
      :ok = Probe.configure(:handoff_successor)
      server = start(c, turn_timeout: :infinity)
      pending = Server.submit(server, signal("blocking_handoff", %{count: 2}))
      assert_receive {:durable_barrier, :handoff_successor, successor}, 5_000

      {_phase, data} = :sys.get_state(server)
      predecessor_id = data.active.handoff_predecessor_id
      successor_id = data.active.turn_id
      assert {:error, :stale_turn} = Server.cancel_turn(server, "stale")

      assert :ok = cancel_handoff(server, selector, predecessor_id, successor_id)
      assert {:error, :cancelled} = Server.await(pending)
      refute Process.alive?(successor)
      assert Process.alive?(server)

      assert {:ok, %{state: %{count: 3}}, []} =
               Server.call(server, signal("handoff", %{count: 2}))

      :ok = Server.stop(server)
    end
  end

  @tag obligation: "jido.agent_server.handoff.I1"
  test "transient successor timeout keeps the server alive", c do
    :ok = Probe.configure(:handoff_successor)
    server = start(c, turn_timeout: 100)
    pending = Server.submit(server, signal("blocking_handoff", %{count: 2}))
    assert_receive {:durable_barrier, :handoff_successor, successor}, 5_000

    assert {:error, :turn_timeout} = Server.await(pending, 1_000)
    refute Process.alive?(successor)
    assert Process.alive?(server)
    assert {:ok, %{state: %{count: 3}}, []} = Server.call(server, signal("handoff", %{count: 2}))
  end

  @tag obligation: "jido.agent_server.handoff.I1"
  test "predecessor effects do not consume the successor timeout", c do
    :ok = Probe.configure(:handoff_effect)
    server = start(c, turn_timeout: 100)
    pending = Server.submit(server, signal("effects_blocking_handoff", %{count: 2}))
    assert_receive {:durable_barrier, :handoff_effect, _effect}, 5_000

    :sys.replace_state(server, fn {:effects, data} ->
      data =
        update_in(data.active.handoff_receipt, fn receipt ->
          Map.put(receipt, :expires_at, System.system_time(:millisecond) - 1)
        end)

      {:effects, data}
    end)

    :ok = Probe.configure(:handoff_successor)
    :ok = Probe.release()
    assert_receive {:durable_barrier, :handoff_successor, _successor}, 5_000

    :ok = Probe.release()
    assert {:ok, %{state: %{count: 3}}, []} = Server.await(pending, 1_000)
  end

  @tag obligation: "jido.agent_server.handoff.I1"
  test "queued work starts after the successor from its committed state", c do
    :ok = Probe.configure(:handoff_successor)
    server = start(c, turn_timeout: :infinity)
    handoff = Server.submit(server, signal("blocking_handoff", %{count: 2}))
    assert_receive {:durable_barrier, :handoff_successor, _successor}, 5_000
    queued = Server.submit(server, signal("increment", %{}))
    assert Server.status(server).admission.postponed == 1

    :ok = Probe.release()
    assert {:ok, %{state: %{count: 3}}, []} = Server.await(handoff)
    assert {:ok, %{state: %{count: 4}}, []} = Server.await(queued)
  end

  @tag obligation: "jido.agent_server.handoff.I1"
  test "the request owner receives predecessor Reply Directives after the successor result", c do
    server = start(c, [])
    request = signal("reply_handoff", %{count: 2})
    pending = Server.submit(server, request, context: %{observer: self()})
    assert_receive {:handoff_reply, output}, 1_000
    output_id = output.id
    refute_received %Jido.Signal{id: ^output_id}

    assert {:ok, %{state: %{count: 3}}, []} = Server.await(pending)

    assert_receive %Jido.Signal{id: ^output_id}, 1_000
  end

  @tag obligation: "jido.agent_server.handoff.I2"
  test "cancellation during a released receipt write accepts every chain selector", c do
    for selector <- [:active, :predecessor, :successor] do
      :ok = EventLog.clear()
      :ok = Probe.configure(:handoff_release_write)
      adapter = {TerminalStorage, path: c.tmp_dir}

      server =
        start(c,
          persistence: adapter,
          persistence_timeout: 5_000,
          turn_timeout: :infinity
        )

      pending = Server.submit(server, signal("blocking_handoff", %{count: 2}))
      assert_receive {:durable_barrier, :handoff_release_write, writer}, 5_000
      {predecessor_id, successor_id} = active_handoff_ids(server)
      assert {:error, :stale_turn} = Server.cancel_turn(server, "stale")

      cancellation =
        Task.async(fn -> cancel_handoff(server, selector, predecessor_id, successor_id) end)

      assert Task.yield(cancellation, 0) == nil
      assert %{active: %{stage: :saving}} = Server.status(server)

      :ok = Probe.release()
      assert :ok = Task.await(cancellation)
      assert {:error, :cancelled} = Server.await(pending)
      refute :blocking_successor_started in EventLog.events()
      refute Process.alive?(writer)
      assert Server.status(server).durable_turn.status == :cancelled
      :ok = Server.stop(server)
    end
  end

  @tag obligation: "jido.agent_server.handoff.I2"
  test "a local checkpoint conflict after release does not start the successor", c do
    :ok = Probe.configure(:handoff_release_write)
    adapter = {TerminalStorage, path: c.tmp_dir}

    server =
      start(c,
        persistence: adapter,
        persistence_timeout: 5_000,
        turn_timeout: :infinity
      )

    pending = Server.submit(server, signal("blocking_handoff", %{count: 2}))
    assert_receive {:durable_barrier, :handoff_release_write, writer}, 5_000
    {:saving, data} = :sys.get_state(server)
    :ets.insert(data.activation_state, {:checkpoint, data.agent, data.state_version + 99})
    :ok = Probe.configure(:handoff_successor)
    :ok = Probe.release()

    assert {:error, _reason} = Server.await(pending, 5_000)
    refute_received {:durable_barrier, :handoff_successor, _}
    refute Process.alive?(writer)
  end

  @tag obligation: "jido.agent_server.handoff.I2"
  test "terminal Handoff persistence does not block committed reads", c do
    :ok = Probe.configure(:handoff_terminal_write)
    adapter = {TerminalStorage, path: c.tmp_dir}
    server = start(c, persistence: adapter, persistence_timeout: 5_000)
    pending = Server.submit(server, signal("effects_failing_handoff", %{count: 2}))
    assert_receive {:durable_barrier, :handoff_terminal_write, writer}, 5_000

    read = Task.async(fn -> {Server.agent(server), Server.status(server)} end)

    assert {:ok, {%Jido.Agent{state: %{count: 0}}, %{active: %{stage: :saving}}}} =
             Task.yield(read, 100)

    :ok = Probe.release()
    assert {:error, _} = Server.await(pending)
    refute Process.alive?(writer)
    assert Process.alive?(server)
  end
end
