defmodule JidoTest.Observe.CausalTraceTest do
  use JidoTest.Case, async: false
  @moduletag capability: "OBS-02"

  alias Jido.Agent.Directive
  alias Jido.Agent.Directive.{EmitToChild, SpawnAgent}
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.CausalTrace, as: Agent
  alias Jido.Examples.TurnObservation.EventProbe
  alias Jido.Tracing.Trace
  alias JidoTest.RemoteChildFixtures, as: Fixtures

  test "pure evaluation leaves trace creation and lifecycle events to the runtime" do
    agent = Agent.new!(id: unique_id())
    probe = EventProbe.attach(agent.id)

    try do
      assert {:ok, candidate, directives} =
               Agent.cmd(agent, Agent.start_work_signal!("request-1", 7))

      assert candidate.state.request_id == "request-1"
      assert agent.state.request_id == ""

      assert [%SpawnAgent{tag: :left}, %EmitToChild{}, %SpawnAgent{tag: :right}, %EmitToChild{}] =
               directives

      for %EmitToChild{signal: signal} <- directives,
          do: assert(Jido.Tracing.Trace.get(signal) == nil)

      assert EventProbe.events(probe) == []
    after
      EventProbe.detach(probe)
    end
  end

  test "work and result Turns retain one trace and distinct causal spans", c do
    with_events(c, fn events, _server, _probe ->
      [parent] = turns(events, "causal.begin")
      children = turns(events, "causal.compute")
      results = turns(events, "causal.result")
      assert length(children) == 2
      assert length(results) == 2
      all = [parent | children ++ results]
      assert Enum.uniq(Enum.map(all, & &1.trace_id)) == [parent.trace_id]
      assert Enum.all?(children, &(&1.parent_span_id == parent.span_id))

      assert Enum.sort(Enum.map(results, & &1.parent_span_id)) ==
               Enum.sort(Enum.map(children, & &1.span_id))

      for key <- [:turn_id, :signal_id, :span_id] do
        assert length(Enum.uniq(Enum.map(all, &Map.fetch!(&1, key)))) == 5
      end

      refute inspect(events) =~ "private-causal-agent-state"

      for event <- events do
        refute Map.has_key?(event.metadata, :signal)
        refute Map.has_key?(event.metadata, :state)
      end
    end)
  end

  test "child-start Turns retain the trace of the spawning parent Turn", c do
    with_events(c, fn events, _server, _probe ->
      [parent] = turns(events, "causal.begin")
      started = turns(events, "jido.agent.child.started")
      assert length(started) == 2

      assert Enum.all?(started, &(&1.trace_id == parent.trace_id)),
             "OBS-02: child work and results complete, but ChildStarted notifications begin unrelated traces. " <>
               inspect(%{
                 parent_trace: parent.trace_id,
                 started_traces: Enum.map(started, & &1.trace_id)
               })

      assert Enum.all?(started, &(&1.parent_span_id == parent.span_id))
    end)
  end

  test "child activation and notification expose the cause without changing source identity", c do
    with_events(c, fn events, _server, _probe ->
      [parent] = turns(events, "causal.begin")
      started = turns(events, "jido.agent.child.started")

      activations =
        for %{
              event: [:jido, :agent, :lifecycle, :stop],
              metadata: %{operation: :activate, agent_id: id} = meta
            } <- events,
            id != parent.agent_id,
            do: meta

      assert length(activations) == 2

      for event <- started ++ activations do
        assert event.trace_id == parent.trace_id
        assert event.parent_span_id == parent.span_id
        assert event.causation_id == parent.signal_id
        assert event.cause_turn_id == parent.turn_id
      end

      for event <- started do
        assert event.source_signal_id == event.signal_id
        refute event.source_signal_id == parent.signal_id
        assert event.child_activation_id in Enum.map(activations, & &1.activation_id)
      end

      assert length(Enum.uniq(Enum.map(started ++ activations, & &1.span_id))) == 4
    end)
  end

  test "local OTP restart retains its cause and replacement uses a new cause", c do
    id = unique_id()
    probe = EventProbe.attach([id, id <> "/worker"])

    try do
      assert {:ok, parent} = Jido.start_agent(c.jido, Fixtures.Parent, id: id)
      directive = Directive.spawn_agent(Agent.Worker, :worker, restart: :permanent)
      first_signal = signal("test.remote.directive", %{directive: directive})
      assert {:ok, _} = Server.call(parent, first_signal)
      first = eventually(fn -> Server.children(parent)[:worker] end)

      eventually(fn ->
        length(turns(EventProbe.events(probe), "jido.agent.child.started")) == 1
      end)

      ref = Process.monitor(first.pid)
      Process.exit(first.pid, :kill)
      assert_receive {:DOWN, ^ref, :process, _, :killed}

      second =
        eventually(fn ->
          case Server.children(parent)[:worker] do
            %{pid: pid} = child when pid != first.pid -> child
            _ -> nil
          end
        end)

      events =
        eventually(fn ->
          events = EventProbe.events(probe)
          if length(turns(events, "jido.agent.child.started")) == 2, do: events
        end)

      [cause] = turns(events, "test.remote.directive")
      [start, restart] = turns(events, "jido.agent.child.started")

      for event <- [start, restart] do
        assert event.causation_id == first_signal.id
        assert event.cause_turn_id == cause.turn_id
        assert event.trace_id == cause.trace_id
        assert event.parent_span_id == cause.span_id
      end

      refute restart.child_activation_id == start.child_activation_id
      refute restart.span_id == start.span_id
      refute restart.signal_id == start.signal_id

      assert :ok = Server.stop_child(parent, :worker)
      replacement_signal = signal("test.remote.directive", %{directive: directive})
      assert {:ok, _} = Server.call(parent, replacement_signal)

      events =
        eventually(fn ->
          events = EventProbe.events(probe)
          if length(turns(events, "jido.agent.child.started")) == 3, do: events
        end)

      replacement = List.last(turns(events, "jido.agent.child.started"))
      assert replacement.causation_id == replacement_signal.id
      refute replacement.trace_id == cause.trace_id
      refute Server.children(parent).worker.pid == second.pid
    after
      EventProbe.detach(probe)
    end
  end

  test "local restore retains the runtime binding cause", c do
    id = unique_id()
    probe = EventProbe.attach([id, id <> "/worker"])

    try do
      assert {:ok, parent} = Jido.start_agent(c.jido, Fixtures.Parent, id: id)
      directive = Directive.spawn_agent(Agent.Worker, :worker, restart: :temporary)
      command = signal("test.remote.directive", %{directive: directive})
      assert {:ok, _} = Server.call(parent, command)
      first = eventually(fn -> Server.children(parent)[:worker] end)

      eventually(fn ->
        length(turns(EventProbe.events(probe), "jido.agent.child.started")) == 1
      end)

      ref = Process.monitor(first.pid)
      Process.exit(first.pid, :kill)
      assert_receive {:DOWN, ^ref, :process, _, :killed}
      eventually(fn -> Server.children(parent) == %{} end)
      assert {:ok, restored} = Jido.start_agent(c.jido, Agent.Worker, id: first.id)

      events =
        eventually(fn ->
          events = EventProbe.events(probe)
          if length(turns(events, "jido.agent.child.started")) == 2, do: events
        end)

      [first_start, restored_start] = turns(events, "jido.agent.child.started")
      assert restored_start.trace_id == first_start.trace_id
      assert restored_start.causation_id == command.id
      refute restored_start.child_activation_id == first_start.child_activation_id
      assert Server.children(parent).worker.pid == restored
    after
      EventProbe.detach(probe)
    end
  end

  test "a restored relationship without a recorded cause keeps root behavior", c do
    id = unique_id()
    probe = EventProbe.attach([id, id <> "/worker"])

    try do
      assert {:ok, parent} = Jido.start_agent(c.jido, Fixtures.Parent, id: id)
      assert {:ok, _} = Server.call(parent, signal("jido.agent.child.ping"))

      assert :ok =
               Jido.RuntimeStore.put(c.jido, :agent_relationships, id <> "/worker", %{
                 parent_id: id,
                 tag: :worker,
                 meta: %{}
               })

      assert {:ok, _child} = Jido.start_agent(c.jido, Agent.Worker, id: id <> "/worker")

      events =
        eventually(fn ->
          events = EventProbe.events(probe)
          if length(turns(events, "jido.agent.child.started")) == 1, do: events
        end)

      [started] = turns(events, "jido.agent.child.started")
      [previous] = turns(events, "jido.agent.child.ping")
      refute started.trace_id == previous.trace_id
      refute Map.has_key?(started, :cause_turn_id)
      refute Map.has_key?(started, :causation_id)
    after
      EventProbe.detach(probe)
    end
  end

  test "a later child command uses its own trace and an explicit retry retains its cause", c do
    with_events(c, fn events, server, probe ->
      [creation] = turns(events, "causal.begin")
      child = Server.children(server).left
      # The caller supplies the trace for its own retry. Agents do not invent it.
      original = Trace.new_root()
      failed = Agent.Worker.compute_signal!("private-causal-request-data", :left, "bad value")
      {:ok, failed} = Trace.put(failed, original)
      assert {:error, _} = Server.call(child.pid, failed)
      retry = Agent.Worker.compute_signal!("private-causal-request-data", :left, 9)
      {:ok, retry} = Trace.put(retry, Trace.child_of(original, failed.id))
      assert {:ok, _} = Server.call(child.pid, retry)
      assert Server.agent(child.pid).state.value == 18
      independent = Agent.Worker.compute_signal!("private-causal-request-data", :left, 10)
      assert {:ok, _} = Server.call(child.pid, independent)

      events =
        eventually(fn ->
          events =
            Enum.filter(EventProbe.events(probe), &(Enum.take(&1.event, 2) == [:jido, :agent]))

          if Enum.any?(turns(events, "causal.compute"), &(&1.signal_id == independent.id)),
            do: events
        end)

      observed = Map.new(turns(events, "causal.compute"), &{&1.signal_id, &1})
      failure = observed[failed.id]
      retried = observed[retry.id]
      fresh = observed[independent.id]
      assert failure.status == :error
      assert retried.status == :ok
      assert failure.trace_id == original.trace_id
      assert retried.trace_id == failure.trace_id
      assert retried.parent_span_id == failure.span_id
      assert retried.causation_id == failed.id
      refute retried.turn_id == failure.turn_id
      refute retried.span_id == failure.span_id
      refute fresh.trace_id in [creation.trace_id, original.trace_id]
      refute Map.has_key?(fresh, :cause_turn_id)
      refute inspect(events) =~ "private-causal-request-data"
    end)
  end

  defp with_events(c, fun) do
    id = unique_id()
    probe = EventProbe.attach([id, id <> "/left", id <> "/right"])

    try do
      assert {:ok, server} = Jido.start_agent(c.jido, Agent, id: id)
      assert {:ok, _} = Agent.start_work(server, "private-causal-request-data", 7)
      eventually(fn -> Server.agent(server).state.results == %{left: 14, right: 14} end)

      events =
        eventually(fn ->
          events =
            Enum.filter(EventProbe.events(probe), &(Enum.take(&1.event, 2) == [:jido, :agent]))

          if Enum.count(events, &(&1.event == [:jido, :agent, :turn, :settled])) == 7, do: events
        end)

      assert Map.keys(Server.children(server)) |> Enum.sort() == [:left, :right]
      refute inspect(events) =~ "private-causal-request-data"
      fun.(events, server, probe)
    after
      EventProbe.detach(probe)
    end
  end

  defp turns(events, type) do
    for %{event: [:jido, :agent, :turn, :settled], metadata: %{signal_type: ^type} = metadata} <-
          events,
        do: metadata
  end
end
