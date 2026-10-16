Code.require_file("support.ex", __DIR__)

defmodule JidoTest.AgentServer2.RequestsTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server2", async: false

  alias Jido.AgentServer2, as: Server
  alias JidoTest.AgentServer2.Fixtures, as: F

  setup do
    F.setup_runtime()
  end

  @tag obligation: ["jido.agent_server2.I4", "jido.agent_server2.I5", "jido.agent_server2.I7"]
  test "reads stay committed and status excludes private context during execution", c do
    server = F.start(c)
    signal = F.signal(%{mode: :gate})
    token = make_ref()
    pending = Server.submit(server, signal, context: [observer: self(), token: token])
    assert_receive {:executing, action, context, input}, 1_000
    assert context.token == token
    assert context.agent_state === c.agent.state
    assert context.signal === signal
    assert input == signal.data
    assert Server.agent(server) === c.agent
    status = Server.status(server)
    assert status.agent_id == c.agent.id
    assert status.phase == :running
    assert status.state_version == 0
    assert status.active.signal_id == signal.id
    assert status.active.turn_id == context.turn_id
    assert status.active.start_version == 0
    assert status.active.committed_version == nil

    assert Map.keys(status.active) |> Enum.sort() ==
             Enum.sort([
               :turn_id,
               :signal_id,
               :start_version,
               :committed_version,
               :stage,
               :worker_pid
             ])

    send(action, :release)
    assert {:ok, agent, []} = Server.await(pending, 1_000)
    assert agent.state === %{c.agent.state | count: 1}
    assert Enum.sort(Map.keys(agent.state)) == [:count, :probe]
    assert %{state_version: 1, active: nil, phase: :idle} = Server.status(server)
    F.clean(c.runner)
  end

  @tag obligation: ["jido.agent_server2.I6", "jido.agent_server2.I7", "jido.agent_server2.I20"]
  test "Action and Flow turns serialize and each starts from the preceding commit", c do
    server = F.start(c)
    first = F.blocked(server, c.runner)
    second = Server.submit(server, F.signal(%{amount: 3}, "flow"), context: %{observer: self()})
    assert %{admission: %{postponed: 1}} = Server.status(server)
    refute_received {:executing, _, _, _}
    F.release(first)
    assert {:ok, %{state: %{count: 1}}, []} = Server.await(first.pending, 1_000)
    assert_receive {:executing, _pid, %{agent_state: %{count: 1}}, _}, 1_000
    assert {:ok, %{state: %{count: 4}}, []} = Server.await(second, 1_000)
    assert %{state_version: 2, phase: :idle} = Server.status(server)
    F.clean(c.runner)
  end

  @tag obligation: ["jido.agent_server2.I8", "jido.agent_server2.I20"]
  test "Action and Flow errors and invalid candidates preserve the complete instance", c do
    server = F.start(c)

    for type <- ["work", "flow"], mode <- [:fail, :invalid] do
      assert {:error, _} = Server.call(server, F.signal(%{mode: mode}, type))
      F.unchanged(server, c.agent)
      F.clean(c.runner)
    end

    assert {:error, _} = F.barrier(server)
    F.unchanged(server, c.agent)
    assert {:ok, %{state: %{count: 1}}, []} = Server.call(server, F.signal())
  end

  @tag obligation: ["jido.agent_server2.I7", "jido.agent_server2.I9"]
  test "successful unchanged state increments revision and returns the committed directive batch",
       c do
    server = F.start(c, directive_handler: fn _, _ -> :ok end)

    assert {:ok, agent, [%F.Effect{label: :returned}]} =
             Server.call(server, F.signal(%{mode: :directive}))

    assert agent === c.agent
    assert %{state_version: 1} = Server.status(server)
    assert Process.alive?(server)
  end

  @tag obligation: "jido.agent_server2.I10"
  test "submit returns before completion, await timeout retains reply, owner cannot transfer it",
       c do
    server = F.start(c)
    turn = F.blocked(server, c.runner)
    assert {:error, :timeout} = Server.await(turn.pending, 0)
    assert {:error, _} = Task.async(fn -> Server.await(turn.pending) end) |> Task.await()
    F.release(turn)
    assert {:ok, %{state: %{count: 1}}, []} = Server.await(turn.pending, 1_000)
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server2.I11"
  test "call timeout stops waiting but accepted work can still commit", c do
    server = F.start(c)
    observer = self()

    task =
      Task.async(fn ->
        catch_exit(
          Server.call(server, F.signal(%{mode: :gate}),
            timeout: 30,
            context: %{observer: observer}
          )
        )
      end)

    assert_receive {:executing, action, _context, _}, 1_000
    assert {:timeout, _} = Task.await(task)
    send(action, :release)
    assert {:error, _} = F.barrier(server)
    assert %{state: %{count: 1}} = Server.agent(server)
    assert %{state_version: 1} = Server.status(server)
  end

  @tag obligation: "jido.agent_server2.I12"
  test "abandon removes monitors and prevents late replies without cancelling work", c do
    server = F.start(c)
    {:monitors, before} = Process.info(self(), :monitors)
    turn = F.blocked(server, c.runner)
    assert {:error, _} = Task.async(fn -> Server.abandon(turn.pending) end) |> Task.await()
    assert :ok = Server.abandon(turn.pending)
    assert {:monitors, ^before} = Process.info(self(), :monitors)
    F.release(turn)
    assert {:error, _} = F.barrier(server)
    assert %{state: %{count: 1}} = Server.agent(server)
    refute_received {[:alias | _], _}
    refute_received {:DOWN, _, :process, ^server, _}
  end

  @tag obligation: "jido.agent_server2.I12"
  test "abandon also discards an already queued reply", c do
    server = F.start(c)
    pending = Server.submit(server, F.signal())
    assert {:error, _} = F.barrier(server)
    assert {:messages, messages} = Process.info(self(), :messages)
    assert Enum.any?(messages, &match?({[:alias | _], _}, &1))
    assert :ok = Server.abandon(pending)
    refute_received {[:alias | _], _}
  end

  @tag obligation: ["jido.agent_server2.I13", "jido.agent_server2.I14"]
  test "cast commits, failure preserves state, and a full queue drops excess casts", c do
    server = F.start(c, max_postponed_signals: 0)
    turn = F.blocked(server, c.runner)
    assert :ok = Server.cast(server, F.signal(%{amount: 50}))
    assert %{admission: %{postponed: 0}} = Server.status(server)
    F.release(turn)
    assert {:ok, %{state: %{count: 1}}, []} = Server.await(turn.pending, 1_000)
    Server.stop(server)
    server = F.start(c)
    assert :ok = Server.cast(server, F.signal(%{mode: :fail}))
    assert :ok = Server.cast(server, F.signal(%{amount: 2}))
    assert {:error, _} = F.barrier(server)
    assert %{state: %{count: 2}} = Server.agent(server)
    assert %{state_version: 1} = Server.status(server)
  end

  @tag obligation: "jido.agent_server2.I14"
  test "queue capacity counts postponed turns and excludes active work", c do
    server = F.start(c, max_postponed_signals: 1)
    turn = F.blocked(server, c.runner)
    queued = Server.submit(server, F.signal())
    assert %{admission: %{postponed: 1, limit: 1}} = Server.status(server)
    assert {:error, {:overloaded, %{limit: 1, postponed: 1}}} = Server.call(server, F.signal())
    excess = Server.submit(server, F.signal())
    assert {:error, {:overloaded, _}} = Server.await(excess)
    F.release(turn)
    assert {:ok, _, []} = Server.await(turn.pending, 1_000)
    assert {:ok, %{state: %{count: 2}}, []} = Server.await(queued, 1_000)
    assert %{admission: %{postponed: 0}} = Server.status(server)
  end

  @tag obligation: ["jido.agent_server2.I4", "jido.agent_server2.I14"]
  test "unlimited admission accepts multiple queued turns and nil context", c do
    server = F.start(c, max_postponed_signals: :infinity)
    turn = F.blocked(server, c.runner)
    queued = for _ <- 1..3, do: Server.submit(server, F.signal(), context: nil)
    assert %{admission: %{postponed: 3, limit: :infinity}} = Server.status(server)
    F.release(turn)
    assert {:ok, _, []} = Server.await(turn.pending, 1_000)

    for {pending, count} <- Enum.with_index(queued, 2) do
      assert {:ok, %{state: %{count: ^count}}, []} = Server.await(pending, 1_000)
    end

    assert %{state_version: 4, admission: %{postponed: 0}} = Server.status(server)
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server2.I15"
  test "expired work never executes; active work outlives its admission budget", c do
    server = F.start(c)
    assert {:error, :admission_timeout} = Server.call(server, F.signal(), admission_timeout: 0)

    active =
      Server.submit(server, F.signal(%{mode: :gate}),
        admission_timeout: 50,
        context: %{observer: self()}
      )

    assert_receive {:executing, action, _, _}, 1_000

    expired =
      Server.submit(server, F.signal(),
        admission_timeout: 10,
        context: %{observer: self()}
      )

    assert %{admission: %{postponed: 1}} = Server.status(server)
    F.elapsed(60)
    send(action, :release)
    assert {:ok, %{state: %{count: 1}}, []} = Server.await(active, 1_000)
    assert {:error, :admission_timeout} = Server.await(expired, 1_000)
    assert {:error, _} = F.barrier(server)
    refute_received {:executing, _, _, _}
    assert %{state_version: 1} = Server.status(server)
  end

  @tag obligation: "jido.agent_server2.I16"
  test "direct and nested owned requests fail, while external monitored caller remains valid",
       c do
    server = F.start(c, max_postponed_signals: 0)

    for type <- ["work", "flow"] do
      assert {:ok, _, []} =
               Server.call(server, F.signal(%{mode: :probe}, type),
                 context: %{server: server, observer: self()}
               )

      expected = {List.duplicate({:error, :reentrant_turn}, 4), c.agent.id}
      assert_receive {:probe, ^expected, ^expected}, 1_000
      assert_receive {:executing, _, _, _}, 1_000
    end

    assert {:ok, _, []} = Server.call(server, F.signal())
    assert %{state_version: 3} = Server.status(server)
  end
end
