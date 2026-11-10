defmodule Jido.AgentServer.ApiTest do
  use Covenant.Case, component: "jido.agent_server", async: true

  import Jido.Test.PublicAPI

  alias Jido.AgentServer
  alias Jido.AgentServer.{Lifecycle, Pending, Status}

  @tag obligation: "jido.agent_server.I9"
  test "the documented AgentServer API and public types are exact" do
    assert documented_api(AgentServer) == [
             {:function, :abandon, 1},
             {:function, :activation, 1},
             {:function, :adopt_child, 4},
             {:function, :agent, 2},
             {:function, :alive?, 1},
             {:function, :attach, 3},
             {:function, :await, 2},
             {:function, :await_ready, 2},
             {:function, :call, 3},
             {:function, :cancel, 2},
             {:function, :cancel_turn, 3},
             {:function, :cast, 3},
             {:function, :child_spec, 1},
             {:function, :children, 2},
             {:function, :deliver_wait, 4},
             {:function, :detach, 3},
             {:function, :hibernate, 2},
             {:function, :history, 1},
             {:function, :members, 3},
             {:function, :plugin_state, 3},
             {:function, :quiesce, 2},
             {:function, :resume, 2},
             {:function, :snapshot, 2},
             {:function, :spawn_child, 4},
             {:function, :start, 1},
             {:function, :start_link, 1},
             {:function, :status, 2},
             {:function, :stop, 3},
             {:function, :stop_child, 3},
             {:function, :submit, 3},
             {:function, :touch, 1},
             {:function, :upgrade, 3},
             {:function, :whereis, 3},
             {:function, :worker, 1}
           ]

    assert documented_types(AgentServer) == [
             {:type, :adoption_option, 0},
             {:type, :child_info, 0},
             {:type, :child_option, 0},
             {:type, :child_tag, 0},
             {:type, :pending, 0},
             {:type, :server, 0},
             {:type, :signal_result, 0},
             {:type, :snapshot, 0},
             {:type, :upgrade_option, 0}
           ]

    assert public_module?(AgentServer)
    assert public_module?(Status)

    for module <- [Lifecycle, Pending] do
      refute public_module?(module)
    end
  end
end
