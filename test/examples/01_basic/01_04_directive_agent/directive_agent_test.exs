defmodule JidoTest.Examples.Basic.DirectiveAgentTest do
  use JidoTest.BasicSDKCase

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.DirectiveAgent.{Effects, StatelessEffects}
  alias Jido.Examples.DirectiveAgent, as: Agent

  test "every handler observes committed state and dispatch follows batch order", %{jido: jido} do
    for plugin <- [Effects, StatelessEffects] do
      server = start_agent!(jido, %{Agent.agent() | plugins: [plugin]})
      assert Map.has_key?(Server.children(server), {:plugin, plugin}) == (plugin == Effects)
      command = change(7, :valid)
      assert {:ok, committed} = Server.call(server, command, context: %{observer: self()})
      await_idle(server)
      records = records(server, plugin)

      assert Enum.map(records, & &1.label) == ["first", "second", "third"]

      for record <- records do
        assert record.snapshot == %{agent: committed, state_version: 1}
        assert record.context.state_version == 1
        assert record.context.agent_id == committed.id
        assert record.context.source_signal.id == command.id
      end

      assert records |> Enum.map(& &1.context.turn_id) |> Enum.uniq() |> length() == 1
      assert Server.snapshot(server) == %{agent: committed, state_version: 1}
    end
  end

  test "an invalid later Directive prevents the entire commit and all dispatch", %{jido: jido} do
    for plugin <- [Effects, StatelessEffects] do
      server =
        start_agent!(jido, %{Agent.agent() | plugins: [plugin]}, error_policy: observe_errors())

      before = Server.snapshot(server)

      assert {:error, %Jido.Error.ValidationError{}} =
               Server.call(server, change(7, :invalid), context: %{observer: self()})

      await_idle(server)
      assert Server.snapshot(server) == before
      assert records(server, plugin) == []

      assert {:ok, recovered} =
               Server.call(server, change(2, :valid), context: %{observer: self()})

      await_idle(server)
      assert recovered.state.count == 2
      assert Server.snapshot(server) == %{agent: recovered, state_version: 1}
      assert Enum.map(records(server, plugin), & &1.label) == ["first", "second", "third"]
    end
  end

  test "a failed second dispatch preserves the commit and prevents the third effect", %{
    jido: jido
  } do
    for plugin <- [Effects, StatelessEffects] do
      server =
        start_agent!(jido, %{Agent.agent() | plugins: [plugin]}, error_policy: observe_errors())

      command = change(9, :dispatch_failure)

      assert {:ok, committed} = Server.call(server, command, context: %{observer: self()})
      assert_receive {:sdk_error, %Jido.Error.ExecutionError{}, outcome}, 1_000
      assert outcome.committed?
      assert outcome.source_signal.id == command.id
      assert outcome.state_version_after == 1
      assert outcome.directives.completed == 1
      assert outcome.directives.failed == 1
      assert outcome.directives.skipped == 1
      await_idle(server)

      records = records(server, plugin)
      assert Enum.map(records, & &1.label) == ["first", "second"]
      assert Enum.all?(records, &(&1.snapshot == %{agent: committed, state_version: 1}))
      assert committed.state == %{count: 9}
      assert Server.snapshot(server) == %{agent: committed, state_version: 1}
    end
  end

  defp records(server, Effects), do: Effects.records(server)

  defp records(server, StatelessEffects) do
    receive do
      {:sdk_record, ^server, record} -> [record | records(server, StatelessEffects)]
    after
      0 -> []
    end
  end

  defp change(count, batch), do: Agent.set_count_signal!(count, batch)
end
