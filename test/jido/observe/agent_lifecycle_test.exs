defmodule JidoTest.Observe.AgentLifecycleTest do
  use JidoTest.Case, async: false

  @moduletag capability: "OBS-01"

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.TurnObservation, as: Agent
  alias Jido.Examples.TurnObservation.EventProbe

  test "pure evaluation returns a candidate without Agent runtime events" do
    {:ok, agent} = Agent.new(id: unique_id())
    probe = EventProbe.attach(agent.id)

    try do
      assert {:ok, candidate, []} = Agent.cmd(agent, Agent.record_signal!(7))
      assert candidate.state.value == 7
      assert agent.state.value == 0
      assert EventProbe.events(probe) == []
    after
      EventProbe.detach(probe)
    end
  end

  test "an external telemetry handler failure preserves the command result", %{jido: jido} do
    id = unique_id()
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach_many(
        handler,
        [[:jido, :agent_server, :signal, :start], [:jido, :agent, :turn, :start]],
        &__MODULE__.fail_observer/4,
        {id, self()}
      )

    try do
      {:ok, server} = Jido.start_agent(jido, Agent, id: id)
      assert {:ok, agent} = Agent.record(server, 7)
      assert_receive :observer_failed
      assert agent.state.value == 7
      assert Server.snapshot(server).state_version == 1
      assert Process.alive?(server)
    after
      :telemetry.detach(handler)
    end
  end

  test "each admitted Turn emits a terminal event with its Outcome and revision", %{jido: jido} do
    id = unique_id()
    probe = EventProbe.attach(id)

    try do
      # Debug history is a diagnostic oracle only. It is never the collector's
      # event source, and it cannot satisfy the telemetry acceptance assertion.
      {:ok, server} = Jido.start_agent(jido, Agent, id: id, debug: true)
      success = Agent.record_signal!(7)
      validation = Agent.record_signal!("invalid integer")
      execution = Agent.fail_execution_signal!()
      cancellation = Agent.hold_signal!(99)
      delivery = Agent.send_to_missing_child_signal!(11)

      assert {:ok, _} = Server.call(server, success)
      assert {:error, _} = Server.call(server, validation)
      assert {:error, _} = Server.call(server, execution)
      cancel_held_turn(server, cancellation)
      assert {:ok, _} = Server.call(server, delivery)
      eventually(fn -> Server.status(server).phase == :idle end)
      assert Server.snapshot(server).state_version == 2
      assert Server.agent(server).state.value == 11

      {:ok, history} = Server.recent_events(server)
      outcomes = for %{metadata: %{outcome: outcome}} <- history, do: outcome

      expected = [
        {success.id, :succeeded, true, 0, 1},
        {validation.id, :failed, false, 1, nil},
        {execution.id, :failed, false, 1, nil},
        {cancellation.id, :cancelled, false, 1, nil},
        {delivery.id, :failed, true, 1, 2}
      ]

      assert Enum.sort(Enum.map(outcomes, &outcome_identity/1)) == Enum.sort(expected)
      delivery_outcome = Enum.find(outcomes, &(&1.source_signal.id == delivery.id))
      assert delivery_outcome.stage == :directive
      assert delivery_outcome.directives.failed == 1

      events = EventProbe.events(probe)
      refute inspect(events) =~ "private-agent-state"
      settled = Enum.filter(events, &(&1.event == [:jido, :agent, :turn, :settled]))

      assert length(settled) == length(outcomes),
             "OBS-01: five real Outcomes exist, but SDK terminal events are missing. " <>
               inspect(%{
                 outcomes: Enum.map(outcomes, &outcome_identity/1),
                 observed_events: Enum.map(events, & &1.event),
                 settled: length(settled)
               })

      for outcome <- outcomes do
        assert [event] = Enum.filter(settled, &(&1.metadata.turn_id == outcome.id))
        assert event.metadata.source_signal_id == outcome.source_signal.id
        assert event.metadata.committed? == outcome.committed?
        assert event.metadata.status == public_status(outcome.status)

        assert event.metadata.stage ==
                 if(outcome.stage in [:prepare, :execute, :finalize],
                   do: :evaluate,
                   else: outcome.stage
                 )

        assert is_binary(event.metadata.trace_id)
        assert is_binary(event.metadata.activation_id)
        assert event.measurements.state_version_before == outcome.state_version_before
        assert event.measurements[:state_version_after] == outcome.state_version_after
      end
    after
      EventProbe.detach(probe)
    end
  end

  test "startup, restart, and shutdown are observable without command wrappers", %{jido: jido} do
    id = unique_id()
    probe = EventProbe.attach(id)

    try do
      {:ok, first} = Jido.start_agent(jido, Agent, id: id, restart: :transient)
      assert Server.status(first).phase == :idle
      monitor = Process.monitor(first)
      Process.exit(first, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^first, :killed}, 1_000

      replacement =
        eventually(fn ->
          case Jido.whereis_agent(jido, id) do
            pid when is_pid(pid) and pid != first -> pid
            _ -> false
          end
        end)

      assert Server.status(replacement).phase == :idle
      monitor = Process.monitor(replacement)
      assert :ok = Jido.stop_agent(jido, replacement)
      assert_receive {:DOWN, ^monitor, :process, ^replacement, :shutdown}, 1_000
      eventually(fn -> Jido.whereis_agent(jido, id) == nil end)

      lifecycle =
        Enum.filter(EventProbe.events(probe), fn event ->
          Enum.take(event.event, 3) == [:jido, :agent, :lifecycle]
        end)

      assert lifecycle != [],
             "OBS-01: startup, an OTP restart, and shutdown completed; zero SDK lifecycle events."

      completed =
        for %{event: [:jido, :agent, :lifecycle, :stop], metadata: metadata} <- lifecycle,
            do: metadata.operation

      assert Enum.count(completed, &(&1 == :activate)) == 2
      assert Enum.count(completed, &(&1 == :stop)) == 1

      activations =
        for %{
              event: [:jido, :agent, :lifecycle, :stop],
              metadata: %{operation: :activate, activation_id: id}
            } <- lifecycle,
            do: id

      assert length(Enum.uniq(activations)) == 2
    after
      EventProbe.detach(probe)
    end
  end

  test "commit ends the Turn span and held delivery delays settlement", %{jido: jido} do
    id = unique_id()
    probe = EventProbe.attach(id)
    owner = self()

    deliver = fn value ->
      send(owner, {:delivery_started, self(), value})

      receive do
        :release -> :ok
      end
    end

    try do
      {:ok, server} = Jido.start_agent(jido, Agent, id: id)
      signal = Agent.record_and_deliver_signal!(8)
      assert {:ok, agent} = Server.call(server, signal, context: %{deliver: deliver})
      assert_receive {:delivery_started, worker, 8}, 1_000
      assert agent.state.value == 8
      assert Server.snapshot(server).state_version == 1
      assert Server.status(server).phase == :directing
      before = semantic_events(probe)

      assert Enum.map(before, & &1.event) |> Enum.filter(&(Enum.at(&1, 2) != :lifecycle)) == [
               [:jido, :agent, :turn, :start],
               [:jido, :agent, :commit, :start],
               [:jido, :agent, :commit, :stop],
               [:jido, :agent, :turn, :stop],
               [:jido, :agent, :directive, :start]
             ]

      send(worker, :release)
      eventually(fn -> Server.status(server).phase == :idle end)
      events = semantic_events(probe)

      assert Enum.map(Enum.take(events, -2), & &1.event) == [
               [:jido, :agent, :directive, :stop],
               [:jido, :agent, :turn, :settled]
             ]

      terminal = List.last(events)
      assert terminal.metadata.status == :ok
      assert terminal.metadata.stage == :directive
      assert terminal.measurements.directive_completed == 1
      turns = Enum.filter(events, &Map.has_key?(&1.metadata, :turn_id))
      assert Enum.uniq(Enum.map(turns, & &1.metadata.turn_id)) == [terminal.metadata.turn_id]
      assert Enum.uniq(Enum.map(turns, & &1.metadata.trace_id)) == [terminal.metadata.trace_id]

      for event <- events do
        assert Enum.all?(Map.values(event.measurements), &is_integer/1)
      end
    after
      EventProbe.detach(probe)
    end
  end

  test "semantic events exclude private errors, context, and nonportable partitions", %{
    jido: jido
  } do
    id = unique_id()
    probe = EventProbe.attach(id)
    private = "private-observation-payload"

    failure =
      Jido.Error.execution_error(private,
        details: %{input: private, process: self(), callback: fn -> private end}
      )

    try do
      {:ok, server} = Jido.start_agent(jido, Agent, id: id, partition: %{private: self()})
      command = Agent.fail_execution_signal!()
      trace = Jido.Tracing.Trace.new_root()
      {:ok, command} = Jido.Tracing.Trace.put(command, trace)

      assert {:error, _} =
               Server.call(server, command, context: %{failure: failure, secret: private})

      events = semantic_events(probe)
      refute inspect(events) =~ private

      for event <- events do
        refute Map.has_key?(event.metadata, :partition)

        refute Enum.any?(
                 Map.values(event.metadata),
                 &(is_pid(&1) or is_function(&1) or is_reference(&1) or is_map(&1))
               )

        refute Map.has_key?(event.metadata, :error)
        refute Map.has_key?(event.metadata, :stacktrace)
      end

      [terminal] = Enum.filter(events, &(&1.event == [:jido, :agent, :turn, :settled]))
      assert terminal.metadata.trace_id == trace.trace_id
      assert terminal.metadata.status == :error
      assert terminal.metadata.error_type == :execution_error
      refute Enum.any?(events, &(List.last(&1.event) == :exception))
    after
      EventProbe.detach(probe)
    end
  end

  test "Directive timeout reports a committed terminal outcome", %{jido: jido} do
    id = unique_id()
    probe = EventProbe.attach(id)
    owner = self()

    deliver = fn _value ->
      send(owner, {:delivery_started, self()})

      receive do
        :release -> :ok
      end
    end

    try do
      {:ok, server} = Jido.start_agent(jido, Agent, id: id, directive_timeout: 100)
      assert {:ok, _} = Agent.record_and_deliver(server, 8, context: %{deliver: deliver})
      assert_receive {:delivery_started, worker}, 1_000
      monitor = Process.monitor(worker)
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
      eventually(fn -> Server.status(server).phase == :idle end)
      events = semantic_events(probe)
      [terminal] = Enum.filter(events, &(&1.event == [:jido, :agent, :turn, :settled]))
      assert terminal.metadata.status == :timed_out
      assert terminal.metadata.committed?
      assert terminal.measurements.state_version_after == 1
      assert terminal.measurements.directive_failed == 1
      refute Enum.any?(events, &(List.last(&1.event) == :exception))
    after
      EventProbe.detach(probe)
    end
  end

  test "a requested stop settles active work once before lifecycle completion", %{jido: jido} do
    id = unique_id()
    probe = EventProbe.attach(id)
    owner = self()

    barrier = fn ->
      send(owner, {:held_execution, self()})

      receive do
        :release -> :ok
      end
    end

    try do
      {:ok, server} = Jido.start_agent(jido, Agent, id: id)

      caller =
        Task.async(fn ->
          try do
            Agent.hold(server, 9, context: %{barrier: barrier})
          catch
            :exit, reason -> {:caller_exit, reason}
          end
        end)

      assert_receive {:held_execution, worker}, 1_000
      monitor = Process.monitor(worker)
      assert :ok = Jido.stop_agent(jido, server)
      assert {:caller_exit, _} = Task.await(caller)
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
      events = semantic_events(probe)
      [terminal] = Enum.filter(events, &(&1.event == [:jido, :agent, :turn, :settled]))
      assert terminal.metadata.status == :indeterminate
      refute terminal.metadata.committed?
      assert List.last(events).metadata.operation == :stop
    after
      EventProbe.detach(probe)
    end
  end

  defp semantic_events(probe) do
    Enum.filter(EventProbe.events(probe), &(Enum.take(&1.event, 2) == [:jido, :agent]))
  end

  test "a crashed Directive task emits an exception and one terminal outcome", %{jido: jido} do
    id = unique_id()
    probe = EventProbe.attach(id)
    owner = self()

    deliver = fn _value ->
      send(owner, {:delivery_started, self()})

      receive do
        :release -> :ok
      end
    end

    try do
      {:ok, server} = Jido.start_agent(jido, Agent, id: id)
      assert {:ok, _} = Agent.record_and_deliver(server, 8, context: %{deliver: deliver})
      assert_receive {:delivery_started, worker}, 1_000
      monitor = Process.monitor(worker)
      Process.exit(worker, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 1_000
      eventually(fn -> Server.status(server).phase == :idle end)
      events = semantic_events(probe)
      [fault] = Enum.filter(events, &(&1.event == [:jido, :agent, :directive, :exception]))
      assert fault.metadata.kind == :exit
      refute Map.has_key?(fault.metadata, :stacktrace)
      [terminal] = Enum.filter(events, &(&1.event == [:jido, :agent, :turn, :settled]))
      assert terminal.metadata.status == :error
      assert terminal.metadata.committed?
      assert terminal.measurements.state_version_after == 1
    after
      EventProbe.detach(probe)
    end
  end

  @doc false
  def fail_observer(_event, _measurements, %{agent_id: id}, {id, observer}) do
    send(observer, :observer_failed)
    raise "requested observer failure"
  end

  def fail_observer(_event, _measurements, _metadata, _config), do: :ok

  defp outcome_identity(outcome) do
    {outcome.source_signal.id, outcome.status, outcome.committed?, outcome.state_version_before,
     outcome.state_version_after}
  end

  defp public_status(:succeeded), do: :ok
  defp public_status(:failed), do: :error
  defp public_status(status), do: status

  defp cancel_held_turn(server, signal) do
    owner = self()

    barrier = fn ->
      send(owner, {:held_execution, self()})

      receive do
        :release -> :ok
      end
    end

    caller = Task.async(fn -> Server.call(server, signal, context: %{barrier: barrier}) end)
    assert_receive {:held_execution, worker}, 1_000
    monitor = Process.monitor(worker)
    assert :ok = Server.cancel_turn(server, Server.status(server).active.turn_id)
    assert {:error, :cancelled} = Task.await(caller)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
  end
end
