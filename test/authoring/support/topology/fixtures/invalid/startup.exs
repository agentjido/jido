defmodule JidoTest.Authoring.Topology.Fixtures.Invalid.Startup do
  use Jido.Topology, name: "invalid_startup"

  topology do
    startup do
      concurrency 0
    end
  end
end
