Code.require_file("../support/case.exs", __DIR__)

for adapter <- [:ets, :file, :ecto] do
  defmodule Module.concat(JidoTest.System.CommitProjection, Macro.camelize(to_string(adapter))) do
    use JidoTest.System.Case, async: false
    @moduletag :system
    @moduletag adapter: adapter

    alias Jido.AgentServer, as: Server
    alias Jido.Examples.Plugins.CommitProjection.{Agent, Package, Runtime}
    alias JidoTest.System.Observability

    test "live projection, saved revision, restore, and hook evidence agree", c do
      :ok = Jido.Debug.enable(c.jido, :verbose)
      on_exit(fn -> Jido.Debug.disable(c.jido) end)
      id = unique_id("commit-projection")
      server = start_agent(c, module: Agent, id: id)
      runtime = Map.fetch!(Server.children(server), {:plugin, Package}).pid
      assert Runtime.view(runtime) == {0, 0}

      for {amount, revision} <- [{3, 1}, {0, 2}] do
        signal =
          Jido.Signal.new!("examples.plugins.commit_projection.add", %{amount: amount},
            source: "/system"
          )

        assert {:ok, committed} = Server.call(server, signal)

        {_, _, measurements, metadata} =
          Observability.await(c.observer, fn
            {^server, [:jido, :agent, :turn, :settled], %{state_version_after: ^revision}, _} ->
              true

            _ ->
              false
          end)

        assert metadata.stage == :after_commit
        assert metadata.status == :ok
        assert measurements.directive_count == 0
        assert measurements.directive_failed == 0
        assert Server.status(server).phase == :idle
        assert Runtime.view(runtime) == {3, revision}
        assert {:ok, ^committed, ^revision} = load(c, id, Agent)
        Observability.assert_turn(c.observer, signal, :ok, true, id)

        assert {^server, [:jido, :agent, :after_commit, :stop], _,
                %{plugin_module: Package, status: :ok}} =
                 Observability.await(c.observer, fn
                   {^server, [:jido, :agent, :after_commit, :stop], _, %{turn_id: turn_id}} ->
                     turn_id == metadata.turn_id

                   _ ->
                     false
                 end)

        Observability.await_log(c.observer, fn log ->
          text = inspect(log.msg)
          text =~ "event=agent.after_commit.stop" and text =~ metadata.turn_id
        end)
      end

      kill_agent(c, server)
      restored = start_agent(c, module: Agent, id: id, restore: :required)
      restored_runtime = Map.fetch!(Server.children(restored), {:plugin, Package}).pid
      assert Runtime.view(restored_runtime) == {3, 2}
      assert Server.snapshot(restored).state_version == 2

      refute Enum.any?(Observability.events(c.observer), fn
               {^restored, [:jido, :agent, :after_commit, _], _, _} -> true
               _ -> false
             end)

      stop_agent(c, restored)
      assert_empty_agent_pool(c)
    end
  end
end
