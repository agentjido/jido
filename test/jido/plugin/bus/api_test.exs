defmodule Jido.Plugin.Bus.ApiTest do
  use Covenant.Case, component: "jido.plugin.bus", async: true

  import Jido.Test.PublicAPI

  alias Jido.Plugin.Bus.Client
  alias Jido.Plugin.Bus.Client.Runtime
  alias Jido.Plugin.Bus.Client.Server, as: ClientServer
  alias Jido.Plugin.Bus.DSL
  alias Jido.Plugin.Bus.DSL.References
  alias Jido.Plugin.Bus.Manager
  alias Jido.Plugin.Bus.Manager.Server, as: ManagerServer

  @tag obligation: ["jido.plugin.bus.I1", "jido.plugin.bus.I3", "jido.plugin.bus.I4"]
  test "Bus exposes only its Plugins, DSL, and Client option types" do
    for module <- [DSL, Manager, Client] do
      assert public_module?(module)
      assert documented_api(module) == []
    end

    assert documented_types(DSL) == []
    assert documented_types(Manager) == []

    assert documented_types(Client) == [
             {:type, :option, 0},
             {:type, :start_position, 0}
           ]

    for module <- [References, Runtime, ClientServer, ManagerServer] do
      refute public_module?(module)
    end
  end
end
