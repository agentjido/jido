defmodule Jido.AgentServer.ApiTest do
  use Covenant.Case, component: "jido.agent_server", async: true

  import Jido.Test.PublicAPI

  alias Jido.AgentServer
  alias Jido.AgentServer.{Pending, Snapshot, Status, TurnResult, Worker}

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
