Code.require_file("../../bench/support/fixtures.exs", __DIR__)
Code.require_file("../../bench/support/agent_server2_cases.exs", __DIR__)

defmodule JidoTest.System.AgentServer2LoadTest do
  use JidoTest.Case, async: false
  @moduletag :system
  @moduletag timeout: 120_000
  alias JidoCoreBench.AgentServer2Cases, as: Load

  test "mixed activations release transient input and all declared resources across cycles", c do
    for _ <- 1..2 do
      result = Load.load(c.jido, 100)
      assert result.control_cycles == 100
      assert result.hibernations == 0
      assert result.agents == 100
      assert result.plugin_agents == 50
      assert result.activation_processes == 330
      assert result.idle_process_bytes > 0
      assert result.turns == 20
      assert result.recoveries == 5
      assert Load.clean(c.jido) == :ok
    end
  end
end
