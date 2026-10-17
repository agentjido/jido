Code.require_file("support.ex", __DIR__)

defmodule JidoTest.AgentServer.ObservationTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server2", async: false

  alias Jido.AgentServer, as: Server
  alias Jido.Tracing.Trace
  alias JidoTest.AgentServer.Fixtures, as: F

  setup do
    F.setup_runtime()
  end

  @tag obligation: ["jido.agent_server2.I29", "jido.agent_server2.I34"]
  test "history is opt-in, bounded, chronological, and contains only terminal summaries", c do
    plain = F.start(c)
    assert {:ok, _, []} = Server.call(plain, F.signal())
    assert Server.history(plain) == []
    assert Server.status(plain).last_outcome.status == :succeeded
    Server.stop(plain)

    server = F.start(c, debug: true, debug_max_events: 2)
    signals = for _ <- 1..3, do: F.signal(%{private_input: "PRIVATE_HISTORY"})
    for signal <- signals, do: assert({:ok, _, []} = Server.call(server, signal))
    history = Server.history(server)
    assert Enum.map(history, & &1.signal_id) == Enum.map(tl(signals), & &1.id)
    assert Enum.map(history, & &1.state_version_after) == [2, 3]
    assert Enum.map(history, & &1.state_version_before) == [1, 2]

    for outcome <- history do
      assert outcome.status == :succeeded
      assert outcome.stage == :commit
      assert outcome.committed?
      assert outcome.directive_count == 0
      assert outcome.duration_ms >= 0

      assert Enum.sort(Map.keys(outcome)) ==
               Enum.sort([
                 :turn_id,
                 :signal_id,
                 :status,
                 :stage,
                 :committed?,
                 :state_version_before,
                 :state_version_after,
                 :directive_count,
                 :duration_ms
               ])
    end

    assert Server.status(server).last_outcome == List.last(history)
    refute inspect(history) =~ "PRIVATE_HISTORY"
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server2.I29"
  test "failure, validation, cancellation, and deadline each produce one uncommitted outcome",
       c do
    server = F.start(c, debug: true, turn_timeout: 150)
    assert {:error, _} = Server.call(server, F.signal(%{mode: :fail}))

    assert %{status: :failed, stage: :running, committed?: false} =
             Server.status(server).last_outcome

    assert {:error, _} = Server.call(server, F.signal(%{mode: :invalid}))

    assert %{status: :failed, stage: :settling, committed?: false} =
             Server.status(server).last_outcome

    turn = F.blocked(server, c.runner)
    assert :ok = Server.cancel_turn(server, turn.id)
    assert {:error, :cancelled} = Server.await(turn.pending)
    assert %{status: :cancelled, committed?: false} = Server.status(server).last_outcome
    turn = F.blocked(server, c.runner)
    assert {:error, :turn_timeout} = Server.await(turn.pending)
    assert %{status: :timed_out, committed?: false} = Server.status(server).last_outcome

    assert Enum.map(Server.history(server), & &1.status) == [
             :failed,
             :failed,
             :cancelled,
             :timed_out
           ]

    assert Enum.all?(Server.history(server), &(&1.state_version_after == 0))
    F.unchanged(server, c.agent)
    F.clean(c.runner)
  end

  @tag obligation: ["jido.agent_server2.I29", "jido.agent_server2.I33"]
  test "events follow commit order and trace reaches native Action tasks without raw values", c do
    attach_events()
    server = F.start(c)
    assert_receive {:event, [:jido, :agent_server, :lifecycle, :start], _, %{agent_id: id}}
    assert id == c.agent.id
    assert :proc_lib.get_label(server) == {Server, c.agent.id}
    parent = Trace.new_root()
    {:ok, signal} = Trace.put(F.signal(%{mode: :trace, private_input: "PRIVATE_EVENT"}), parent)
    assert {:ok, _, []} = Server.call(server, signal, context: %{observer: self()})
    assert_receive {:trace, trace, logger}
    assert trace.trace_id == parent.trace_id
    assert trace.parent_span_id == parent.span_id
    assert logger[:trace_id] == trace.trace_id
    assert logger[:span_id] == trace.span_id

    events =
      for _ <- 1..5 do
        assert_receive {:event, event, measurements, metadata}
        refute inspect({measurements, metadata}) =~ "PRIVATE_EVENT"
        assert metadata.trace_id == trace.trace_id
        assert metadata.signal_id == signal.id
        {event, measurements, metadata}
      end

    assert Enum.map(events, &elem(&1, 0)) == [
             [:jido, :agent_server, :turn, :start],
             [:jido, :agent_server, :commit],
             [:jido, :agent_server, :directives, :returned],
             [:jido, :agent_server, :turn, :stop],
             [:jido, :agent_server, :turn, :settled]
           ]

    assert {_, %{state_version_before: 0, state_version_after: 1},
            %{committed?: true, status: :ok}} = List.last(events)

    assert {:error, _} = Server.call(server, F.signal(), context: %{trace_context: parent})
    Server.stop(server)
    assert_receive {:event, [:jido, :agent_server, :lifecycle, :stop], _, _}
    refute_receive {:event, _, _, _}, 10
    F.clean(c.runner)
  end

  @tag obligation: ["jido.agent_server2.I29", "jido.agent_server2.I33"]
  test "lost Worker emits one indeterminate outcome and no commit", c do
    attach_events()
    server = F.start(c)
    turn = F.blocked(server, c.runner)
    ref = Process.monitor(server)
    Process.exit(turn.worker, :kill)
    assert {:error, _} = Server.await(turn.pending)
    assert_receive {:DOWN, ^ref, :process, ^server, _}, 1_000

    assert_receive {:event, [:jido, :agent_server, :turn, :settled], %{state_version_after: 0},
                    %{status: :indeterminate, committed?: false}},
                   1_000

    refute_receive {:event, [:jido, :agent_server, :turn, :settled], _, _}, 10
    refute_receive {:event, [:jido, :agent_server, :commit], _, _}, 10
    F.clean(c.runner)
  end

  @tag obligation: ["jido.agent_server2.I29", "jido.agent_server2.I33"]
  test "committed directive count is observed", c do
    server = F.start(c, debug: true, directive_handler: fn _, _ -> :ok end)
    assert {:ok, _, [_]} = Server.call(server, F.signal(%{mode: :directive}))
    assert %{directive_count: 1, committed?: true} = Server.status(server).last_outcome
    assert Process.alive?(server)
    F.clean(c.runner)
  end

  defp attach_events do
    id = {__MODULE__, make_ref()}

    events = [
      [:lifecycle, :start],
      [:lifecycle, :stop],
      [:turn, :start],
      [:turn, :stop],
      [:turn, :settled],
      [:commit],
      [:directives, :returned]
    ]

    :ok =
      :telemetry.attach_many(
        id,
        Enum.map(events, &([:jido, :agent_server] ++ &1)),
        &__MODULE__.observe/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  def observe(event, measurements, metadata, observer),
    do: send(observer, {:event, event, measurements, metadata})
end
