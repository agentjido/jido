defmodule JidoTest.AgentServer.Composition.ApiTest do
  use Covenant.Case, component: "jido.agent_server.composition", async: true

  import Jido.Test.PublicAPI

  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.Topology

  @tag obligation: "jido.agent_server.composition.I10"
  test "composition stays on the typed AgentServer facade" do
    public_api = MapSet.new(documented_api(Server))

    assert MapSet.subset?(
             MapSet.new([
               {:function, :adopt_child, 4},
               {:function, :children, 2},
               {:function, :members, 3},
               {:function, :spawn_child, 4},
               {:function, :stop_child, 3}
             ]),
             public_api
           )

    public_types = MapSet.new(documented_types(Server))

    assert MapSet.subset?(
             MapSet.new([
               {:type, :adoption_option, 0},
               {:type, :child_info, 0},
               {:type, :child_option, 0},
               {:type, :child_tag, 0}
             ]),
             public_types
           )

    refute public_module?(Topology)
  end
end
