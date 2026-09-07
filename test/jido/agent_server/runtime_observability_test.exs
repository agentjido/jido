defmodule Jido.AgentServer.RuntimeObservabilityTest do
  use JidoTest.Case, async: false

  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias Jido.Agent.Turn.Outcome
  alias Jido.Signal
  alias JidoTest.AgentRuntimeFixtures.RuntimeAgent

  test "records bounded debug events without exposing Server state", %{jido: jido} do
    {:ok, pid} =
      Jido.start_agent(jido, RuntimeAgent,
        id: unique_id("debug"),
        debug: true,
        debug_max_events: 2
      )

    assert {:ok, _agent} = Server.call(pid, signal("runtime.record", %{event: :one}))
    assert {:ok, _agent} = Server.call(pid, signal("runtime.record", %{event: :two}))

    assert {:ok, events} = Server.recent_events(pid)
    assert length(events) == 2
    assert Enum.map(events, & &1.event) == [:turn_completed, :turn_committed]

    assert %Outcome{
             status: :succeeded,
             stage: :commit,
             committed?: true,
             state_version_before: 1,
             state_version_after: 2
           } = hd(events).metadata.outcome

    refute Enum.any?(events, &Map.has_key?(&1, :server_state))

    assert :ok = Server.set_debug(pid, false)
    assert {:error, :debug_not_enabled} = Server.recent_events(pid)
  end

  test "a Stop Directive commits once and does not restart a supervised Agent", %{jido: jido} do
    id = unique_id("stop")
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: id)
    monitor = Process.monitor(pid)

    assert {:ok, agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :stopped,
                 directive: Directive.stop(:normal)
               })
             )

    assert agent.state.events == [:stopped]
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 2_000
    eventually(fn -> Jido.whereis_agent(jido, id) == nil end)
  end

  test "normalizes an arbitrary Stop reason so stale state cannot restart", %{jido: jido} do
    id = unique_id("abnormal-stop")
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: id)
    monitor = Process.monitor(pid)

    assert {:ok, agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :stopped,
                 directive: Directive.stop(:arbitrary_reason)
               })
             )

    assert agent.state.events == [:stopped]
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, :arbitrary_reason}}, 2_000
    eventually(fn -> Jido.whereis_agent(jido, id) == nil end)
  end

  test "rejects a Stop Directive before later effects", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("stop-order"))
    output = Signal.new!("runtime.record", %{event: :must_not_run}, source: "/test")

    assert {:error, {:terminal_directive_not_last, %{index: 0}}} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :must_not_commit,
                 directives: [Directive.stop(), Directive.emit(output)]
               })
             )

    assert Server.agent(pid).state.events == []
    assert Server.status(pid).state_version == 0
  end

  test "emits Agent Signal and Directive telemetry with bounded metadata", %{jido: jido} do
    handler = "agent-runtime-#{System.unique_integer([:positive])}"
    owner = self()

    :ok =
      :telemetry.attach_many(
        handler,
        [
          [:jido, :agent_server, :signal, :stop],
          [:jido, :agent_server, :directive, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(owner, {:agent_telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("telemetry"))
    follow_up = Signal.new!("runtime.record", %{event: :emitted}, source: "/test")

    assert {:ok, _agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :committed,
                 directive: Directive.emit(follow_up)
               })
             )

    assert_receive {:agent_telemetry, [:jido, :agent_server, :signal, :stop], measurements,
                    signal_meta},
                   2_000

    assert is_integer(measurements.duration)
    assert signal_meta.agent_id == Server.agent(pid).id
    assert signal_meta.signal_type == "runtime.directive"
    assert measurements.directive_count == 1
    refute Map.has_key?(signal_meta, :agent)
    refute Map.has_key?(signal_meta, :state)

    assert_receive {:agent_telemetry, [:jido, :agent_server, :directive, :stop], _measurements,
                    directive_meta},
                   2_000

    assert directive_meta.directive_type == "Emit"
  end
end
