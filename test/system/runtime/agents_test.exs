Code.require_file("../support/case.exs", __DIR__)

for adapter <- [:ets, :file, :ecto] do
  defmodule Module.concat(JidoTest.System.Agents, Macro.camelize(to_string(adapter))) do
    use JidoTest.System.Case, async: false
    @moduletag :system
    @moduletag adapter: adapter
    use JidoTest.System.Scenarios.Checkpoints
    use JidoTest.System.Scenarios.Effects
    use JidoTest.System.Scenarios.Fencing
    use JidoTest.System.Scenarios.Recovery
    use JidoTest.System.Scenarios.Execution
    use JidoTest.System.Scenarios.Restoration
    use JidoTest.System.Scenarios.Overload
  end
end
