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
end
