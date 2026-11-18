defmodule Jido.AgentServer.Composition.DurableTopologyHandoffTest do
  use Covenant.Case, component: "jido.agent_server.composition", async: false

  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias Jido.Signal
  alias Jido.Test.AgentServer.DurableFixtures.Probe

  @moduletag :tmp_dir

  defmodule Store do
    @behaviour Jido.Persistence.Store

    defdelegate validate_options(opts), to: Jido.Persistence.File
    defdelegate get(key, opts), to: Jido.Persistence.File
    defdelegate delete(key, opts), to: Jido.Persistence.File

    def compare_and_swap(key, expected, value, opts) do
      prune? = pruning_outbox?(expected, value)

      with :ok <- gate_prune(prune?, :sender_prune),
           :ok <- Jido.Persistence.File.compare_and_swap(key, expected, value, opts),
           :ok <- gate_prune(prune?, :sender_pruned) do
        case Jido.Persistence.Codec.Term.decode(value, trusted: true) do
          {:ok, %{topology_handoffs: %{outbox: [_ | _]}, agent_module: module}} ->
            Probe.gate({:sender_checkpoint, module})

          {:ok, %{server_turn: %{status: :running, id: id}, topology_handoffs: %{accepted: accepted}} = record}
          when is_map_key(accepted, id) ->
            Probe.gate({:receiver_checkpoint, record.agent_module})

          {:ok, {:jido_execution_prepared, 3, %{topology_handoff_id: _}}} ->
            Probe.gate({:receiver_preparation, nil})

          _other ->
            :ok
        end
      end
    end

    defp pruning_outbox?(expected, value) when is_binary(expected) do
      with {:ok, %{agent_rev: revision, topology_handoffs: %{outbox: [_ | remaining]}}} <-
             Jido.Persistence.Codec.Term.decode(expected, trusted: true),
           {:ok, %{agent_rev: ^revision} = next} <- Jido.Persistence.Codec.Term.decode(value, trusted: true) do
        (get_in(next, [:topology_handoffs, :outbox]) || []) == remaining
      else
        _other -> false
      end
    end

    defp pruning_outbox?(_expected, _value), do: false

    defp gate_prune(true, kind), do: Probe.gate({kind, nil})
    defp gate_prune(false, _kind), do: :ok
  end

  defmodule Count do
    use Jido.Flow, name: "topology_handoff_count"

    flow do
      step "count", _input <- input(), inline: [context: context] do
        {:ok, %{count: context.agent_state.count + 1}}
      end

      output result("count")
    end
  end

  defmodule Child do
    use Jido.Agent, name: "topology_handoff_child"

    state do
      schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end

    routes do
      route "count", Count

      route "cast.up" do
        action _input, context: context do
          {:ok, context.agent_state, [Directive.emit(Signal.new!("count", %{}, source: "/child"), :parent)]}
        end
      end

      route "send.up" do
        action _input, context: context do
          {:ok, %{count: context.agent_state.count + 1},
           [Directive.emit(Signal.new!("count", %{}, source: "/child"), {:durable, :parent})]}
        end
      end
    end
  end

  defmodule Root do
    use Jido.Agent, name: "topology_handoff_root"

    state do
      schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end

    routes do
      route "count", Count

      route "send.down" do
        action _input, context: context do
          {:ok, %{count: context.agent_state.count + 1},
           [Directive.emit(Signal.new!("count", %{}, source: "/root"), {:durable, {:agent, :child, 1}})]}
        end
      end

      route "cast.down" do
        action _input, context: context do
          {:ok, context.agent_state, [Directive.emit(Signal.new!("count", %{}, source: "/root"), {:agent, :child})]}
        end
      end
    end

    topology do
      agent :child, Child
    end
  end

  setup %{tmp_dir: path} do
    start_supervised!({Probe, self()})
    instance = Module.concat(__MODULE__, Instance)
    start_supervised!({Jido, name: instance, namespace: "test/topology-handoff", persistence: {Store, path: path}})
    {:ok, address} = Jido.agent_address(instance, "root")
    assert {:ok, ^address} = Jido.create_agent(instance, address, Root)
    assert {:ok, root} = Jido.activate_agent(instance, address)

    child_address = %{address | id: "root/$topology/child/1/initial"}
    assert {:ok, child} = Jido.resolve_agent(instance, child_address)
    %{instance: instance, root: root, child: child, address: address, child_address: child_address, path: path}
  end

  @tag obligation: "jido.agent_server.composition.I12"
  test "the committed sender restarts before attempting delivery", c do
    :ok = Probe.configure(:sender_checkpoint)
    assert :ok = Server.cast(c.root, signal("send.down"))
    assert_receive {:durable_barrier, :sender_checkpoint, _writer}, 2_000

    saved = record(c, c.address)
    assert %{topology_handoffs: %{outbox: [%{id: id, to: to}]}, agent_rev: 1} = saved
    assert %{topology_handoffs: "[REDACTED]"} = Jido.Persistence.Inspector.redact(saved)
    assert to == c.child_address
    refute Map.has_key?(record(c, to), :topology_handoffs)

    kill_worker(c.root)
    root = recovered(c.instance, c.address, c.root)

    eventually(fn -> record(c, to).agent_rev == 1 end)
    assert count(root) == 1
    assert %{topology_handoffs: %{accepted: %{^id => true}}} = record(c, to)
    eventually(fn -> !Map.has_key?(record(c, c.address), :topology_handoffs) end)
  end

  @tag obligation: "jido.agent_server.composition.I12"
  test "receiver restart before acknowledgment recovers child-to-parent acceptance", c do
    :ok = Probe.configure({:receiver_checkpoint, Root})
    assert {:ok, %{status: :committed}} = Server.call(c.child, signal("send.up"))
    assert_receive {:durable_barrier, :receiver_checkpoint, _writer}, 2_000

    assert %{topology_handoffs: %{outbox: [send]}} = record(c, c.child_address)
    assert %{id: id, to: address} = send
    assert address == c.address

    assert %{agent_rev: 0, server_turn: %{id: ^id, status: :running}, topology_handoffs: %{accepted: %{^id => true}}} =
             record(c, c.address)

    kill_worker(c.root)
    root = recovered(c.instance, c.address, c.root)
    eventually(fn -> count(root) == 1 end)
    eventually(fn -> !Map.has_key?(record(c, c.child_address), :topology_handoffs) end)

    # A later Turn may replace the continuation. The acceptance must still deduplicate.
    assert {:ok, %{status: :committed}} = Server.call(root, signal("count"))
    assert :accepted = accept(root, send, offset: -1)
    assert count(root) == 2
    assert %{topology_handoffs: %{accepted: %{^id => true}}} = record(c, c.address)
  end

  @tag obligation: "jido.agent_server.composition.I12"
  test "a retry reuses its preparation after a receiver dies before accepting", c do
    :ok = Probe.configure(:receiver_preparation)
    assert {:ok, %{status: :committed}} = Server.call(c.root, signal("send.down"))
    assert_receive {:durable_barrier, :receiver_preparation, _writer}, 2_000

    assert %{topology_handoffs: %{outbox: [%{id: id}]}} = record(c, c.address)
    refute Map.has_key?(record(c, c.child_address), :topology_handoffs)

    kill_worker(c.child)
    child = recovered(c.instance, c.child_address, c.child)
    eventually(fn -> count(child) == 1 end)
    assert %{topology_handoffs: %{accepted: %{^id => true}}} = record(c, c.child_address)
    eventually(fn -> !Map.has_key?(record(c, c.address), :topology_handoffs) end)
  end

  @tag obligation: "jido.agent_server.composition.I12"
  test "a quiesced receiver keeps the send recoverable", c do
    assert {:ok, _status} = Server.quiesce(c.child)
    assert {:ok, %{status: :committed}} = Server.call(c.root, signal("send.down"))
    assert %{topology_handoffs: %{outbox: [send]}} = record(c, c.address)

    assert {:error, :topology_receiver_busy} = accept(c.child, send)

    assert %{topology_handoffs: %{outbox: [^send]}} = record(c, c.address)
    assert count(c.child) == 0

    eventually(fn -> match?({_, %{topology_delivery: :scheduled}}, :sys.get_state(c.root)) end)
    assert {:ok, _status} = Server.quiesce(c.root)
    eventually(fn -> match?({_, %{topology_delivery: :ready}}, :sys.get_state(c.root)) end)

    assert {:ok, _status} = Server.resume(c.child)
    assert {:ok, _status} = Server.resume(c.root)
    eventually(fn -> count(c.child) == 1 end)
    eventually(fn -> !Map.has_key?(record(c, c.address), :topology_handoffs) end)
    assert count(c.root) == 1
  end

  @tag obligation: "jido.agent_server.composition.I12"
  test "an expired or malformed delivery does not admit a Turn", c do
    send = %{id: Jido.Id.uuid7(), to: c.child_address, signal: signal("count")}

    assert {:error, :admission_timeout} = accept(c.child, send, offset: -1)
    assert {:error, :invalid_topology_handoff} = accept(c.child, %{send | signal: nil})
    assert count(c.child) == 0
    refute Map.has_key?(record(c, c.child_address), :topology_handoffs)

    assert :accepted = accept(c.child, send)
    eventually(fn -> count(c.child) == 1 end)
    assert :accepted = accept(c.child, send, offset: -1)
    assert count(c.child) == 1
  end

  @tag obligation: "jido.agent_server.composition.I12"
  test "a confirmed prune rejection leaves the sender available and retries cleanup", c do
    :ok = Probe.configure(:sender_prune)
    assert {:ok, %{status: :committed}} = Server.call(c.root, signal("send.down"))
    assert_receive {:durable_barrier, :sender_prune, _writer}, 2_000

    assert %{topology_handoffs: %{outbox: [%{id: id}]}} = record(c, c.address)
    assert %{topology_handoffs: %{accepted: %{^id => true}}} = record(c, c.child_address)
    :ok = Probe.release({:error, {:rejected, :offline}})

    assert {:ok, %{status: :committed}} = Server.call(c.root, signal("count"))
    eventually(fn -> !Map.has_key?(record(c, c.address), :topology_handoffs) end)
    assert count(c.root) == 2
    eventually(fn -> count(c.child) == 1 end)
    assert {:ok, c.root} == Jido.resolve_agent(c.instance, c.address)
  end

  @tag obligation: "jido.agent_server.composition.I12"
  test "an uncertain prune fences the sender until reconciliation reads the committed record", c do
    :ok = Probe.configure(:sender_pruned)
    assert {:ok, %{status: :committed}} = Server.call(c.root, signal("send.down"))
    assert_receive {:durable_barrier, :sender_pruned, _writer}, 2_000

    eventually(fn -> count(c.child) == 1 end)
    refute Map.has_key?(record(c, c.address), :topology_handoffs)
    :ok = Probe.release({:error, :indeterminate})
    eventually(fn -> Jido.resolve_agent(c.instance, c.address) == {:error, :reconciliation_required} end)

    assert {:ok, root} = Jido.reconcile_agent(c.instance, c.address)
    assert count(root) == 1
    assert {:ok, child} = Jido.resolve_agent(c.instance, c.child_address)
    eventually(fn -> count(child) == 1 end)
  end

  @tag obligation: "jido.agent_server.composition.I12"
  test "a slot marked for removal rejects new durable sends before commit", c do
    :ok = :sys.suspend(c.child)

    try do
      assert {:error, {:topology_removal_incomplete, _reason}} =
               Server.remove_topology_member(c.root, :child, 1, timeout: 50)

      assert {:ok, %{status: :failed}} = Server.call(c.root, signal("send.down"))
      assert count(c.root) == 0
      refute Map.has_key?(record(c, c.address), :topology_handoffs)
    after
      :ok = :sys.resume(c.child)
    end
  end

  @tag obligation: "jido.agent_server.composition.I12"
  test "regular topology casts work without persistence while durable sends fail before commit" do
    instance = Module.concat(__MODULE__, Memory)
    start_supervised!({Jido, name: instance})
    assert {:ok, root} = Jido.start_agent(instance, Root, id: "memory-root")
    assert :ok = Server.await_ready(root)
    context = :gen_statem.call(root, :child_context)
    assert [child] = Server.Topology.members(context.state, :child)

    assert {:ok, %{status: :failed}} = Server.call(root, signal("send.down"))
    assert count(root) == 0
    assert {:ok, %{status: :committed}} = Server.call(root, signal("cast.down"))
    eventually(fn -> count(child) == 1 end)
    assert {:ok, %{status: :committed}} = Server.call(child, signal("cast.up"))
    eventually(fn -> count(root) == 1 end)
  end

  defp accept(receiver, send, opts \\ []) do
    deadline = {node(), System.monotonic_time(:millisecond) + Keyword.get(opts, :offset, 5_000)}
    :gen_statem.call(receiver, {:accept_topology_handoff, send.id, send.to, send.signal, deadline})
  end

  defp signal(type), do: Signal.new!(type, %{}, source: "/test")
  defp count(pid), do: Server.snapshot(pid).agent.state.count

  defp record(c, address) do
    {:ok, bytes} = Jido.Persistence.File.get(Jido.Persistence.agent_key(address), path: c.path)
    {:ok, record} = Jido.Persistence.Codec.Term.decode(bytes, [])
    record
  end

  defp kill_worker(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 2_000
  end

  defp recovered(instance, address, old) do
    eventually(fn ->
      case Jido.resolve_agent(instance, address) do
        {:ok, pid} when pid != old -> pid
        _other -> false
      end
    end)
  end

  defp eventually(fun, attempts \\ 200)
  defp eventually(fun, 0), do: flunk("Condition did not become true: #{inspect(fun.())}")

  defp eventually(fun, attempts) do
    case fun.() do
      false ->
        Process.sleep(20)
        eventually(fun, attempts - 1)

      result ->
        result
    end
  end
end
