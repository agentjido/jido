defmodule Jido.AgentServer.ApiTest do
  use Jido.Test.Case, async: true
  use Covenant.Case, component: "jido.agent_server", async: true

  import Jido.Test.PublicAPI

  alias Jido.AgentServer
  alias Jido.AgentServer.{Pending, Snapshot, Status, TurnResult, Worker}

  defmodule QueueAgent do
    use Jido.Agent, name: "admission_queue"

    state do
      schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end

    routes do
      route "queue.work" do
        action input, context: context do
          if input.block do
            send(context.observer, {:queue_gate, self()})

            receive do
              :release -> :ok
            end
          end

          {:ok, %{count: context.agent_state.count + 1}}
        end
      end
    end
  end

  defmodule ChangingName do
    def whereis_name({initial, replacement}) do
      resolved = Process.get(__MODULE__, initial)
      Process.put(__MODULE__, replacement)
      resolved
    end
  end

  @tag obligation: "jido.agent_server.I14"
  test "each submission uses a queue slot even when Turn IDs match", c do
    assert {:ok, server} = Jido.start_agent(c.jido, QueueAgent, id: "queue", max_postponed_signals: 1)
    assert :ok = AgentServer.await_ready(server)

    active =
      AgentServer.submit(server, signal("queue.work", %{block: true}),
        turn_id: "shared",
        context: %{observer: self()}
      )

    assert_receive {:queue_gate, action}, 1_000

    [queued | excess] =
      for _ <- 1..4 do
        AgentServer.submit(server, signal("queue.work", %{block: false}), turn_id: "shared")
      end

    assert %{queue_depth: 1, active_turn_id: "shared"} = AgentServer.status(server)

    for request <- excess do
      assert {:error, {:overloaded, %{limit: 1, postponed: 1}}} = AgentServer.await(request, 500)
    end

    send(action, :release)
    assert {:ok, %{status: :committed}} = AgentServer.await(active)
    assert {:ok, %{status: :committed}} = AgentServer.await(queued)
    assert AgentServer.snapshot(server).agent.state.count == 2
  end

  @tag obligation: "jido.agent_server.I106"
  test "stop finishes the accepted Turn while admission stays closed", c do
    assert {:ok, server} = Jido.start_agent(c.jido, QueueAgent, id: "stop")
    assert :ok = AgentServer.await_ready(server)
    root = Jido.Test.AgentServer.Assertions.activation(server)

    active =
      AgentServer.submit(server, signal("queue.work", %{block: true}),
        turn_id: "active",
        context: %{observer: self()}
      )

    assert_receive {:queue_gate, action}, 1_000
    queued = AgentServer.submit(server, signal("queue.work", %{block: false}), turn_id: "queued")
    assert %{queue_depth: 1} = AgentServer.status(server)
    assert {:error, :stale_turn} = AgentServer.cancel_turn(server, queued.turn_id)

    stop = Task.async(fn -> AgentServer.stop(server) end)
    assert {:error, :quiesced} = AgentServer.await(queued)
    assert {:error, :not_quiescent} = AgentServer.resume(server)
    assert {:error, :quiesced} = AgentServer.call(server, signal("queue.work", %{block: false}))

    send(action, :release)
    assert {:ok, %TurnResult{status: :committed}} = AgentServer.await(active)
    assert {:ok, %Snapshot{agent_revision: 1, agent: %{state: %{count: 1}}}} = Task.await(stop)
    refute Process.alive?(root)
  end

  @tag obligation: "jido.agent_server.I106"
  test "stop keeps its original activation when a registered name changes", c do
    assert {:ok, initial} = Jido.start_agent(c.jido, QueueAgent, id: "initial")
    assert {:ok, replacement} = Jido.start_agent(c.jido, QueueAgent, id: "replacement")
    assert :ok = AgentServer.await_ready(initial)
    assert :ok = AgentServer.await_ready(replacement)
    root = Jido.Test.AgentServer.Assertions.activation(initial)
    name = {:via, ChangingName, {initial, replacement}}

    assert {:ok, %Snapshot{agent: %{id: "initial"}}} = AgentServer.stop(name, :review_stop)
    refute Process.alive?(root)
    assert %Status{admission: :open} = AgentServer.status(replacement)
  end

  @tag obligation: "jido.agent_server.I107"
  test "quiesce closes the reply gates for a queued call and submission", c do
    assert {:ok, server} = Jido.start_agent(c.jido, QueueAgent, id: "quiesce")
    assert :ok = AgentServer.await_ready(server)

    active =
      AgentServer.submit(server, signal("queue.work", %{block: true}), context: %{observer: self()})

    assert_receive {:queue_gate, action}, 1_000
    queued_signal = signal("queue.work", %{block: false})
    pending = AgentServer.submit(server, queued_signal)
    %{reply_gate: pending_gate} = Process.get({Pending, pending.request_id})
    observer = self()

    caller =
      spawn_link(fn ->
        send(observer, {:call_result, AgentServer.call(server, queued_signal)})

        receive do
          :finished -> :ok
        end
      end)

    assert_eventually(AgentServer.status(server).queue_depth == 2)

    [call_gate] =
      eventually(fn ->
        server_monitors = monitors_of(server)
        Enum.find_value(monitors_of(caller), fn pid -> if pid in server_monitors, do: [pid] end)
      end)

    control = Task.async(fn -> AgentServer.quiesce(server) end)
    assert {:error, :quiesced} = AgentServer.await(pending)
    assert_receive {:call_result, {:error, :quiesced}}, 1_000

    send(action, :release)
    assert {:ok, %TurnResult{status: :committed}} = AgentServer.await(active)
    assert {:ok, %Status{admission: :quiesced, queue_depth: 0}} = Task.await(control)
    assert Process.alive?(caller)
    refute_eventually(Process.alive?(pending_gate))
    refute_eventually(Process.alive?(call_gate))

    assert {:ok, %Status{admission: :open}} = AgentServer.resume(server)
    assert %Snapshot{agent_revision: 1} = AgentServer.snapshot(server)
    send(caller, :finished)
  end

  @tag obligation: "jido.agent_server.I107"
  test "a call to an absent registered name leaves no reply gate" do
    name = :jido_agent_server_api_test_absent
    queued_signal = signal("queue.work", %{block: false})
    monitors_before = monitors_of(self())

    assert {:noproc, _} = catch_exit(AgentServer.call(name, queued_signal))
    assert_eventually(monitors_of(self()) -- monitors_before == [])
  end

  @tag obligation: "jido.agent_server.I107"
  test "a submission to an absent registered name leaves no reply gate" do
    name = :jido_agent_server_api_test_absent
    queued_signal = signal("queue.work", %{block: false})

    pending = AgentServer.submit(name, queued_signal)
    %{reply_gate: gate} = Process.get({Pending, pending.request_id})
    assert {:error, %Jido.Error.ExecutionError{}} = AgentServer.await(pending)
    refute_eventually(Process.alive?(gate))
  end

  @tag obligation: "jido.agent_server.I9"
  test "the documented AgentServer API and public types are exact" do
    assert documented_api(AgentServer) == [
             {:function, :abandon, 1},
             {:function, :await, 2},
             {:function, :await_ready, 2},
             {:function, :call, 3},
             {:function, :cancel_turn, 3},
             {:function, :cast, 3},
             {:function, :child_spec, 1},
             {:function, :quiesce, 2},
             {:function, :remove_topology_member, 4},
             {:function, :resume, 2},
             {:function, :snapshot, 2},
             {:function, :status, 2},
             {:function, :stop, 3},
             {:function, :submit, 3}
           ]

    assert documented_types(AgentServer) == [
             {:type, :server, 0}
           ]

    for module <- [AgentServer, Pending, Snapshot, Status, TurnResult] do
      assert public_module?(module)
    end

    for module <- [Worker] do
      refute public_module?(module)
    end
  end

  defp monitors_of(pid), do: elem(Process.info(pid, :monitored_by), 1)
end
