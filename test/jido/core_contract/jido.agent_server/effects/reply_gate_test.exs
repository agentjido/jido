defmodule JidoTest.AgentServer.Effects.ReplyGateTest do
  use Covenant.Case, component: "jido.agent_server.effects", async: true

  alias Jido.Agent.Directive
  alias Jido.AgentServer.Effects
  alias Jido.AgentServer.ReplyGate
  alias Jido.Signal

  @tag obligation: "jido.agent_server.effects.I13"
  test "the Reply effect adds correlation and does not use the fallback handler" do
    signal = Signal.new!("reply.gate", %{value: 1}, source: "/test/reply-gate")
    directive = Directive.reply(signal)
    request_id = Signal.ID.generate!()

    context = %{
      agent: %{id: "reply-gate-agent", state: %{}},
      turn_id: Signal.ID.generate!(),
      signal_id: request_id,
      state_version: 1,
      plugin_specs: [],
      plugin_refs: %{},
      source_signal: signal,
      effective_signal: signal,
      turn_context: %{},
      jido: nil,
      partition: nil
    }

    result =
      Jido.Tracing.Context.with_context(Jido.Tracing.Trace.new_root(), fn ->
        Effects.run(directive, fn _, _ -> flunk("Reply used the fallback handler") end, context)
      end)

    assert {:reply, delivered} = result

    assert Map.drop(Map.from_struct(delivered), [:extensions]) ==
             Map.drop(Map.from_struct(signal), [:extensions])

    assert Signal.get_context(delivered, "jidocausationid") == request_id
    assert Signal.Trace.get(delivered) != nil
  end

  @tag obligation: "jido.agent_server.effects.I13"
  test "the gate buffers in order, opens once, and then delivers directly" do
    server = process()
    gate = ReplyGate.start(self(), server)
    first = {:reply_gate, :first, make_ref()}
    second = {:reply_gate, :second, make_ref()}
    third = {:reply_gate, :third, make_ref()}

    assert :ok = ReplyGate.deliver(nil, first)
    assert :ok = ReplyGate.done(nil)
    assert :ok = ReplyGate.deliver(gate, first)
    assert :ok = ReplyGate.deliver(gate, second)
    refute_receive ^first, 20
    refute_receive ^second, 20

    assert_request(fn -> ReplyGate.open(gate) end)
    assert_receive ^first, 100
    assert_receive ^second, 100

    assert :ok = ReplyGate.deliver(gate, third)
    assert_receive ^third, 100
    assert :ok = ReplyGate.done(gate)
    assert_down(gate)
    stop(server)
  end

  @tag obligation: "jido.agent_server.effects.I13"
  test "done waits for a buffered owner and leaves no request monitor message" do
    server = process()
    empty_gate = ReplyGate.start(self(), server)
    assert :ok = ReplyGate.done(empty_gate)
    assert_down(empty_gate)

    gate = ReplyGate.start(self(), server)
    signal = {:reply_gate, :buffered, make_ref()}
    parent = self()

    assert :ok = ReplyGate.deliver(gate, signal)
    assert :ok = ReplyGate.done(gate)
    Process.sleep(10)
    assert Process.alive?(gate)

    opener =
      Task.async(fn ->
        assert :ok = ReplyGate.open(gate)
        send(parent, {:reply_gate_opened, self()})

        receive do
          {:DOWN, _ref, :process, ^gate, _reason} -> :leaked_monitor
        after
          50 -> :clean
        end
      end)

    assert_receive ^signal, 100
    assert_receive {:reply_gate_opened, opener_pid}, 100
    assert opener.pid == opener_pid
    assert :clean = Task.await(opener, 200)
    refute Process.alive?(gate)
    stop(server)
  end

  @tag obligation: "jido.agent_server.effects.I13"
  test "abandon drops buffered and future signals before or after done" do
    server = process()
    buffered = {:reply_gate, :buffered, make_ref()}
    future = {:reply_gate, :future, make_ref()}
    gate = ReplyGate.start(self(), server)

    assert :ok = ReplyGate.deliver(gate, buffered)
    assert_request(fn -> ReplyGate.abandon(gate) end)
    assert :ok = ReplyGate.deliver(gate, future)
    assert :ok = ReplyGate.done(gate)
    assert_down(gate)
    refute_receive ^buffered, 20
    refute_receive ^future, 20

    after_done = ReplyGate.start(self(), server)
    queued = {:reply_gate, :done_then_abandon, make_ref()}
    assert :ok = ReplyGate.deliver(after_done, queued)
    assert :ok = ReplyGate.done(after_done)
    Process.sleep(10)
    assert Process.alive?(after_done)
    assert_request(fn -> ReplyGate.abandon(after_done) end)
    assert_down(after_done)
    refute_receive ^queued, 20
    stop(server)
  end

  @tag obligation: "jido.agent_server.effects.I13"
  test "owner and server monitors close the gate at the correct boundary" do
    server = process()
    owner = process()
    owner_gate = ReplyGate.start(owner, server)
    stop(owner)
    assert_down(owner_gate)

    empty_server = process()
    empty_gate = ReplyGate.start(self(), empty_server)
    stop(empty_server)
    assert_down(empty_gate)

    buffered_server = process()
    buffered_gate = ReplyGate.start(self(), buffered_server)
    signal = {:reply_gate, :server_stopped, make_ref()}
    assert :ok = ReplyGate.deliver(buffered_gate, signal)
    stop(buffered_server)
    Process.sleep(10)
    assert Process.alive?(buffered_gate)
    assert_request(fn -> ReplyGate.open(buffered_gate) end)
    assert_receive ^signal, 100
    assert_down(buffered_gate)
    stop(server)
  end

  defp assert_request(fun) do
    task = Task.async(fun)

    case Task.yield(task, 100) do
      {:ok, :ok} ->
        :ok

      result ->
        Task.shutdown(task, :brutal_kill)
        flunk("ReplyGate request did not return :ok: #{inspect(result)}")
    end
  end

  defp assert_down(pid) do
    monitor = Process.monitor(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 100
  end

  defp process do
    spawn(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end

  defp stop(pid) do
    if Process.alive?(pid), do: send(pid, :stop)
    :ok
  end
end
