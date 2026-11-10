defmodule Jido.AgentServer.Perf.LoadTest do
  use Jido.Test.Case, async: false

  @moduletag :load
  @moduletag timeout: 180_000

  alias Jido.AgentServer, as: Server

  defmodule Increment do
    use Jido.Action,
      name: "runtime_load_increment",
      schema: Jido.Joi.object(%{amount: Jido.Joi.integer()})

    @impl true
    def run(%{amount: amount}, %{agent_state: state, observer: observer, run_ref: run_ref}) do
      send(observer, {run_ref, :started, amount, self()})

      receive do
        {^run_ref, :release} -> {:ok, %{count: state.count + amount}}
      after
        30_000 -> raise "load command was not released"
      end
    end
  end

  defmodule Counter do
    use Jido.Agent, name: "runtime_load_counter"

    state do
      schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end

    routes do
      route "runtime.load.increment", Increment
    end
  end

  test "repeated 100-Agent cycles overlap commands and release all activation processes", c do
    results =
      for cycle <- 1..3 do
        started = System.monotonic_time(:microsecond)

        servers =
          for index <- 1..100 do
            {:ok, server} =
              Jido.Test.AgentServer.Assertions.start_agent(c.jido, Counter, id: unique_id("load-#{cycle}-#{index}"))

            server
          end

        observer = self()
        run_ref = make_ref()

        calls =
          servers
          |> Enum.take(20)
          |> Enum.with_index(1)
          |> Enum.map(fn {server, index} ->
            Task.async(fn ->
              result =
                Server.call(server, signal("runtime.load.increment", %{amount: index}),
                  timeout: 60_000,
                  context: %{observer: observer, run_ref: run_ref}
                )

              {index, result}
            end)
          end)

        # Every Action must be running before any Action can complete.
        actions =
          for index <- 1..20 do
            assert_receive {^run_ref, :started, ^index, pid}, 10_000
            pid
          end

        assert MapSet.size(MapSet.new(actions)) == 20
        Enum.each(actions, &send(&1, {run_ref, :release}))

        for call <- calls do
          assert {index, {:ok, %{state: %{count: count}}, []}} = Task.await(call, 60_000)
          assert count == index
        end

        monitored =
          servers
          |> Enum.flat_map(&[&1, Server.activation(&1)])
          |> Enum.uniq()
          |> Enum.map(&{&1, Process.monitor(&1)})

        servers
        |> Task.async_stream(&Jido.stop_agent(c.jido, &1),
          max_concurrency: 32,
          timeout: 60_000
        )
        |> Enum.each(&assert(&1 == {:ok, :ok}))

        Enum.each(monitored, fn {pid, monitor} ->
          assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 10_000
        end)

        assert Jido.agent_count(c.jido) == 0
        assert Jido.list_agents(c.jido) == []
        assert DynamicSupervisor.which_children(test_agent_supervisor(c)) == []

        %{
          cycle: cycle,
          agents: length(servers),
          concurrent_commands: length(calls),
          monitored_processes: length(monitored),
          elapsed_us: System.monotonic_time(:microsecond) - started
        }
      end

    IO.puts("Runtime load: " <> JSON.encode!(results))
  end
end
