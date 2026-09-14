Code.require_file("../support/case.exs", __DIR__)

for adapter <- [:ets, :file, :ecto] do
  defmodule Module.concat(JidoTest.System.Topology, Macro.camelize(to_string(adapter))) do
    use JidoTest.System.Case, async: false
    @moduletag :system
    @moduletag adapter: adapter
    use JidoTest.System.Scenarios.Topology
  end
end
