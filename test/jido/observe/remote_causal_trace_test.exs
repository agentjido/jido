defmodule JidoTest.Observe.RemoteCausalTraceTest do
  use JidoTest.PeerCase, async: false
  @moduletag capability: "OBS-02"

  alias Jido.AgentServer, as: Server
  alias Jido.Agent.Directive
  alias Jido.Examples.CausalTrace, as: Agent
  alias JidoTest.CausalTraceFixtures, as: Probe
  alias JidoTest.RemoteChildFixtures, as: Fixtures

  test "two remote children retain work, result, activation, and notification causes", c do
    probes = probes(c, ["parent", "parent/left", "parent/right"])

    assert {:ok, parent} =
             peer_call(c.peer_a, Jido, :start_agent, [c.jido, Agent, [id: "parent"]])

    assert {:ok, _} =
             peer_call(c.peer_a, Agent, :start_work, [
               parent,
               "private-remote-input",
               7,
               [input: %{node: c.node_b}]
             ])

    eventually(
      fn ->
        peer_call(c.peer_a, Server, :agent, [parent]).state.results == %{left: 14, right: 14}
      end,
      timeout: 3_000
    )

    for {_tag, child} <- peer_call(c.peer_a, Server, :children, [parent]),
        do: assert(node(child.pid) == c.node_b)

    events = await_turns(c, probes, 7)
    [cause] = turns(events, "causal.begin")
    work = turns(events, "causal.compute")
    results = turns(events, "causal.result")
    started = turns(events, "jido.agent.child.started")
    activations = activations(events, "parent")
    assert length(work) == 2
    assert length(results) == 2
    assert length(started) == 2
    assert length(activations) == 2

    for event <- work ++ started ++ activations do
      assert event.trace_id == cause.trace_id
      assert event.parent_span_id == cause.span_id
      assert event.causation_id == cause.signal_id
    end

    for event <- started ++ activations, do: assert(event.cause_turn_id == cause.turn_id)

    assert Enum.sort(Enum.map(results, & &1.parent_span_id)) ==
             Enum.sort(Enum.map(work, & &1.span_id))

    for event <- results, do: assert(event.trace_id == cause.trace_id)

    for key <- [:signal_id, :turn_id, :span_id] do
      assert length(
               Enum.uniq(Enum.map([cause | work ++ results ++ started], &Map.fetch!(&1, key)))
             ) == 7
    end

    for event <- started,
        do: assert(event.child_activation_id in Enum.map(activations, & &1.activation_id))

    refute inspect(events) =~ "private-remote-input"
    refute inspect(events) =~ "private-causal-agent-state"
  end

  test "late startup after a retry retains the original request cause", c do
    probes = probes(c, ["parent", "parent/worker"])

    assert {:ok, parent} =
             peer_call(c.peer_a, Fixtures, :start_parent, [
               c.jido,
               [id: "parent", directive_timeout: 100]
             ])

    supervisor = Jido.agent_supervisor_name(c.jido)
    assert :ok = peer_call(c.peer_b, :sys, :suspend, [supervisor])
    directive = Directive.spawn_agent(Agent.Worker, :worker, node: c.node_b)

    try do
      first = dispatch(c, parent, directive)
      [first_turn] = turns(await_turns(c, probes, 1), "test.remote.directive")
      assert first_turn.status == :indeterminate
      retry = dispatch(c, parent, directive)
      [_, retry_turn] = turns(await_turns(c, probes, 2), "test.remote.directive")
      assert retry_turn.status == :indeterminate
      refute first.id == retry.id
      refute first_turn.turn_id == retry_turn.turn_id
      refute first_turn.trace_id == retry_turn.trace_id
      assert :ok = peer_call(c.peer_b, :sys, :resume, [supervisor])
      events = await_turns(c, probes, 3)
      [started] = turns(events, "jido.agent.child.started")
      [activation] = activations(events, "parent")

      for event <- [started, activation] do
        assert event.trace_id == first_turn.trace_id
        assert event.parent_span_id == first_turn.span_id
        assert event.causation_id == first.id
        assert event.cause_turn_id == first_turn.turn_id
      end

      assert map_size(peer_call(c.peer_a, Server, :children, [parent])) == 1
      assert length(peer_call(c.peer_b, DynamicSupervisor, :which_children, [supervisor])) == 1
    after
      peer_call(c.peer_b, :sys, :resume, [supervisor])
    end
  end

  test "remote OTP restart has a new activation and the original creation cause", c do
    probes = probes(c, ["parent", "parent/worker"])
    assert {:ok, parent} = peer_call(c.peer_a, Fixtures, :start_parent, [c.jido, [id: "parent"]])

    command =
      dispatch(
        c,
        parent,
        Directive.spawn_agent(Agent.Worker, :worker, node: c.node_b, restart: :permanent)
      )

    events = await_turns(c, probes, 2)
    [cause] = turns(events, "test.remote.directive")
    first = peer_call(c.peer_a, Server, :children, [parent]).worker
    peer_call(c.peer_b, Process, :exit, [first.pid, :kill])

    events =
      eventually(fn ->
        events = events(c, probes)
        if length(turns(events, "jido.agent.child.started")) == 2, do: events
      end)

    starts = turns(events, "jido.agent.child.started")
    activations = activations(events, "parent")
    assert length(activations) == 2

    for event <- starts ++ activations do
      assert event.trace_id == cause.trace_id
      assert event.parent_span_id == cause.span_id
      assert event.causation_id == command.id
      assert event.cause_turn_id == cause.turn_id
    end

    assert length(Enum.uniq(Enum.map(starts, & &1.child_activation_id))) == 2
    assert length(Enum.uniq(Enum.map(starts, & &1.span_id))) == 2
    assert length(Enum.uniq(Enum.map(activations, & &1.activation_id))) == 2
    next = peer_call(c.peer_a, Server, :children, [parent]).worker
    refute next.pid == first.pid
    assert node(next.pid) == c.node_b
  end

  test "a failed remote creation emits a failed attempt without a child-start event", c do
    probes = probes(c, ["parent", "parent/worker"])
    assert {:ok, parent} = peer_call(c.peer_a, Fixtures, :start_parent, [c.jido, [id: "parent"]])
    assert :ok = peer_call(c.peer_b, Supervisor, :terminate_child, [Jido.Supervisor, c.jido])
    command = dispatch(c, parent, Directive.spawn_agent(Agent.Worker, :worker, node: c.node_b))
    events = await_turns(c, probes, 1)
    [failure] = turns(events, "test.remote.directive")
    assert failure.signal_id == command.id
    assert failure.status == :error
    assert failure.committed?

    [directive] =
      for %{event: [:jido, :agent, :directive, :stop], metadata: meta} <- events, do: meta

    assert directive.trace_id == failure.trace_id
    assert directive.turn_id == failure.turn_id
    assert directive.status == :error
    assert turns(events, "jido.agent.child.started") == []
    assert activations(events, "parent") == []
    assert peer_call(c.peer_a, Server, :children, [parent]) == %{}
  end

  defp dispatch(c, parent, directive) do
    signal = Jido.Signal.new!("test.remote.directive", %{directive: directive}, source: "/test")
    assert {:ok, _} = peer_call(c.peer_a, Server, :call, [parent, signal])
    signal
  end

  defp probes(c, ids) do
    for peer <- [c.peer_a, c.peer_b] do
      assert {:ok, probe} = peer_call(peer, Probe, :start_probe, [ids])
      {peer, probe}
    end
  end

  defp events(_c, probes),
    do: Enum.flat_map(probes, fn {peer, probe} -> peer_call(peer, Probe, :events, [probe]) end)

  defp await_turns(c, probes, count) do
    eventually(
      fn ->
        events = events(c, probes)

        if Enum.count(events, &(&1.event == [:jido, :agent, :turn, :settled])) == count,
          do: events
      end,
      timeout: 3_000
    )
  end

  defp turns(events, type) do
    for %{event: [:jido, :agent, :turn, :settled], metadata: %{signal_type: ^type} = meta} <-
          events,
        do: meta
  end

  defp activations(events, parent) do
    for %{
          event: [:jido, :agent, :lifecycle, :stop],
          metadata: %{operation: :activate, agent_id: id} = meta
        } <- events,
        id != parent,
        do: meta
  end
end
