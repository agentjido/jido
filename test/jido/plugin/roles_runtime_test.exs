defmodule Jido.Plugin.RolesRuntimeTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer, as: Server
  alias JidoTest.CommitProjection, as: Fixture

  defmodule LocalFirst do
    use Jido.Plugin, roles: [:agent, :agent_server]
    defdelegate state_spec(opts), to: Fixture.AgentFacet
    defdelegate directives(opts), to: Fixture.AgentFacet
    defdelegate reduce(reduction, opts), to: Fixture.AgentFacet
    defdelegate after_commit(runtime, commit, opts), to: Fixture.ServerFacet
    defdelegate dispatch(runtime, directive, context, opts), to: Fixture.ServerFacet
  end

  defmodule LocalSecond do
    use Jido.Plugin, roles: [:agent, :agent_server]
    defdelegate state_spec(opts), to: Fixture.AgentFacet
    defdelegate directives(opts), to: Fixture.AgentFacet
    defdelegate reduce(reduction, opts), to: Fixture.AgentFacet
    defdelegate after_commit(runtime, commit, opts), to: Fixture.NotificationFacet
  end

  defmodule RuntimeFacet do
    use Jido.AgentServer.Plugin
    defdelegate child_spec(init), to: Fixture.RuntimeFacet
    defdelegate after_commit(runtime, commit, opts), to: Fixture.RuntimeFacet

    def await_ready(runtime, opts) do
      send(opts[:observer], {:ready, self(), runtime})

      receive do
        :ready -> :ok
      end
    end
  end

  defmodule SeparateRuntime do
    use Jido.Plugin, agent: Fixture.AgentFacet, agent_server: RuntimeFacet
  end

  defmodule LocalRuntime do
    use Jido.Plugin, roles: [:agent, :agent_server]
    defdelegate state_spec(opts), to: Fixture.AgentFacet
    defdelegate reduce(reduction, opts), to: Fixture.AgentFacet
    defdelegate child_spec(init), to: RuntimeFacet
    defdelegate after_commit(runtime, commit, opts), to: RuntimeFacet
    defdelegate await_ready(runtime, opts), to: RuntimeFacet
  end

  setup do
    Process.register(self(), __MODULE__.Observer)
    sink = __MODULE__.Sink

    start_supervised!(%{
      id: sink,
      start: {Elixir.Agent, :start_link, [fn -> [] end, [name: sink]]}
    })

    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(handler, [:jido, :agent, :turn, :settled], &__MODULE__.observe/4, self())

    on_exit(fn -> :telemetry.detach(handler) end)
    %{sink: sink}
  end

  def observe(_event, _measurements, metadata, observer), do: send(observer, {:settled, metadata})

  for {first, second} <- [{Fixture.First, Fixture.Second}, {LocalFirst, LocalSecond}] do
    @first first
    @second second

    test "#{inspect(first)} preserves commit order, state, and failed-Turn isolation", %{
      jido: jido,
      sink: sink
    } do
      {:ok, server} = Jido.start_agent(jido, definition(@first, @second, sink), id: unique_id())
      assert {:ok, committed} = Server.call(server, update(3, sink))
      assert committed.state == %{count: 3, first: 3, second: 3}
      settle(server)

      assert [{:commit, @first, nil, first}, {:commit, @second, nil, second}, :effect] =
               history(sink)

      assert first.plugin_state == second.plugin_state
      assert first.state_version == second.state_version
      assert first.state_version == 1
      assert first.turn_id == second.turn_id

      assert {:error, _} = Server.call(server, signal("projection.reject"))
      settle(server)
      assert Server.snapshot(server) == %{agent: committed, state_version: 1}
      assert length(history(sink)) == 3
    end

    for failure <- [:error, :timeout] do
      @failure failure
      test "#{inspect(first)} #{@failure} skips later hooks and Directives after successful commit",
           %{jido: jido, sink: sink} do
        observer = self()

        policy = fn reason, outcome ->
          send(observer, {:policy, reason, outcome})
          :continue
        end

        opts =
          if @failure == :error,
            do: [result: :error],
            else: [gate: "blocked", observer: __MODULE__.Observer]

        definition = definition(@first, @second, sink, opts)

        {:ok, server} =
          Jido.start_agent(jido, definition,
            id: unique_id(),
            directive_timeout: 100,
            error_policy: policy
          )

        assert {:ok, committed} = Server.call(server, update(7, sink))
        assert committed.state == %{count: 7, first: 7, second: 7}

        if @failure == :timeout do
          assert_receive {:commit_started, _, worker}
          ref = Process.monitor(worker)
          assert_receive {:DOWN, ^ref, :process, ^worker, _}, 2_000
        end

        assert_receive {:policy, reason, outcome}, 2_000

        if @failure == :error,
          do: assert(reason == :projection_unavailable),
          else: assert(match?(%Jido.Error.TimeoutError{}, reason))

        assert outcome.stage == :after_commit
        assert outcome.committed?

        assert outcome.directives == %{
                 total: 1,
                 completed: 0,
                 failed: 0,
                 skipped: 1,
                 failed_index: nil
               }

        settle(server)
        assert Server.snapshot(server) == %{agent: committed, state_version: 1}
        assert [{:commit, @first, nil, _}] = history(sink)
      end
    end
  end

  for package <- [SeparateRuntime, LocalRuntime] do
    @package package
    test "#{inspect(package)} gates readiness, replaces with fresh state, and stops its runtime",
         %{jido: jido} do
      definition = %{
        Fixture.Agent.definition()
        | plugins: [{@package, key: :projection, observer: __MODULE__.Observer}]
      }

      starter =
        Task.async(fn ->
          Jido.start_agent(jido, definition, id: unique_id(), restart: :temporary)
        end)

      assert_receive {:projection_init, runtime,
                      %{module: @package, plugin_state: 0, state_version: 0}},
                     2_000

      assert_receive {:ready, waiter, ^runtime}, 2_000
      send(waiter, :ready)
      assert {:ok, server} = Task.await(starter)
      assert :ok = Server.await_ready(server)
      assert {:ok, committed} = Server.call(server, signal("projection.update", %{amount: 4}))
      settle(server)
      assert GenServer.call(runtime, :view) == {4, 1}
      ref = Process.monitor(runtime)
      Process.exit(runtime, :kill)
      assert_receive {:DOWN, ^ref, :process, ^runtime, :killed}
      assert_receive {:projection_init, replacement, init}, 2_000
      assert init.plugin_state == committed.state.projection
      assert init.state_version == 1
      assert_receive {:ready, replacement_waiter, ^replacement}, 2_000

      eventually(fn ->
        Server.await_ready(server) == {:error, {:plugin_runtime_restarting, @package}}
      end)

      send(replacement_waiter, :ready)
      eventually(fn -> Server.await_ready(server) == :ok end)
      assert GenServer.call(replacement, :view) == {4, 1}
      replacement_ref = Process.monitor(replacement)
      assert :ok = Server.stop(server)
      assert_receive {:DOWN, ^replacement_ref, :process, ^replacement, _}, 2_000
    end

    test "#{inspect(package)} stops a blocked readiness task and runtime on timeout", %{
      jido: jido
    } do
      definition = %{
        Fixture.Agent.definition()
        | plugins: [{@package, key: :projection, observer: __MODULE__.Observer}]
      }

      starter =
        Task.async(fn ->
          Jido.start_agent(jido, definition,
            id: unique_id(),
            readiness_timeout: 100,
            restart: :temporary
          )
        end)

      assert_receive {:projection_init, runtime, _}, 2_000
      assert_receive {:ready, waiter, ^runtime}, 2_000
      refs = for pid <- [runtime, waiter], do: {Process.monitor(pid), pid}

      assert {:error, {:plugin_readiness_failed, %Jido.Error.TimeoutError{}}} =
               Task.await(starter)

      for {ref, pid} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 2_000)
    end
  end

  defp definition(first, second, sink, opts \\ []) do
    %{
      Fixture.Agent.definition()
      | plugins: [{first, [key: :first, sink: sink] ++ opts}, {second, key: :second, sink: sink}]
    }
  end

  defp update(amount, sink),
    do: signal("projection.update", %{amount: amount, directives: [%Fixture.Effect{sink: sink}]})

  defp history(sink), do: Elixir.Agent.get(sink, & &1)

  defp settle(server) do
    assert_receive {:settled, _}, 2_000
    assert Server.status(server).phase == :idle
  end
end
