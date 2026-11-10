defmodule Jido.AgentServer.Durable.ApiTest do
  use Covenant.Case, component: "jido.agent_server.durable", async: true

  import Jido.Test.PublicAPI

  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.Lifecycle

  @tag obligation: "jido.agent_server.durable.I13"
  test "durable operations stay on the typed AgentServer facade" do
    public_api = MapSet.new(documented_api(Server))

    assert MapSet.subset?(
             MapSet.new([
               {:function, :hibernate, 2},
               {:function, :snapshot, 2},
               {:function, :upgrade, 3}
             ]),
             public_api
           )

    public_types = MapSet.new(documented_types(Server))

    assert MapSet.subset?(
             MapSet.new([
               {:type, :snapshot, 0},
               {:type, :upgrade_option, 0}
             ]),
             public_types
           )

    refute public_module?(Lifecycle)
  end
end
