defmodule JidoTest.Authoring.Topology.Fixtures.Plugin do
  use Jido.Topology, name: "authoring_plugin"

  topology do
    agents do
      agent :solo, JidoTest.Authoring.Topology.Fixtures.PluginWorker
      group :workers, JidoTest.Authoring.Topology.Fixtures.PluginWorker, count: 2
    end
  end
end
