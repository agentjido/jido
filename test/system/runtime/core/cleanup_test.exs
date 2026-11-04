Code.require_file("support/counter.exs", __DIR__)

defmodule JidoTest.System.Runtime.CleanupTest do
  use JidoTest.Case, async: false

  @moduletag :system
  @moduletag timeout: 120_000

  alias Jido.AgentServer, as: Server
  alias JidoTest.System.Runtime.Counter

  test "three pressure cycles release every AgentServer tree and registry entry", c do
    for cycle <- 1..3 do
      servers =
        for index <- 1..50 do
          id = unique_id("cleanup-#{cycle}-#{index}")
          {:ok, server} = JidoTest.AgentServerAssertions.start_agent(c.jido, Counter, id: id)
          assert {:ok, next, []} = Server.call(server, signal("system.runtime.add", %{delta: index}))
          assert next.state.count == index
          server
        end

      monitors =
        Enum.flat_map(servers, fn server ->
          [server, Server.activation(server)]
          |> Enum.uniq()
          |> Enum.map(&{&1, Process.monitor(&1)})
        end)

      servers
      |> Task.async_stream(&Jido.stop_agent(c.jido, &1),
        max_concurrency: 16,
        timeout: 30_000
      )
      |> Enum.each(&assert(&1 == {:ok, :ok}))

      Enum.each(monitors, fn {pid, monitor} ->
        assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 5_000
      end)

      assert Jido.list_agents(c.jido) == []
      assert Jido.agent_count(c.jido) == 0
      assert DynamicSupervisor.which_children(test_agent_supervisor(c)) == []
    end
  end
end
