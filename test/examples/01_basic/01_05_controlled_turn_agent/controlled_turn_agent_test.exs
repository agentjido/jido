defmodule JidoTest.Examples.Basic.ControlledTurnAgentTest do
  use JidoTest.BasicSDKCase

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.DirectiveAgent.Effects
  alias Jido.Examples.ControlledTurnAgent, as: Agent

  test "queued work starts with the prior Turn's committed state", %{jido: jido} do
    server = start_agent!(jido, Agent)
    before = Server.snapshot(server)
    observer = self()
    first_signal = change("first", 2, true)

    caller =
      Task.async(fn ->
        Server.call(server, first_signal,
          context: %{observer: observer, request: "first context"}
        )
      end)

    assert_receive {:sdk_started, "first", first_worker, initial, "first context"}, 1_000
    assert initial == before.agent.state

    second_caller =
      Task.async(fn ->
        Server.call(server, change("second", 3, true),
          context: %{observer: observer, request: "second context"}
        )
      end)

    eventually(fn -> Server.status(server).admission.postponed == 1 end)
    assert Server.snapshot(server) == before
    assert Effects.records(server) == []
    refute_received {:sdk_started, "second", _, _, _}

    send(first_worker, {:sdk_release, "first"})
    assert {:ok, first} = Task.await(caller)
    assert_receive {:sdk_started, "second", second_worker, second_input, "second context"}, 1_000
    assert second_input == first.state
    assert Server.snapshot(server) == %{agent: first, state_version: 1}

    assert [%{label: "first", snapshot: %{agent: ^first, state_version: 1}}] =
             Effects.records(server)

    send(second_worker, {:sdk_release, "second"})
    assert {:ok, _} = Task.await(second_caller)
    eventually(fn -> Server.snapshot(server).state_version == 2 end)
    await_idle(server)
    assert Server.agent(server).state == %{count: 5, history: ["first", "second"]}
    assert Enum.map(Effects.records(server), & &1.label) == ["first", "second"]
  end

  test "cancellation terminates abandoned work and preserves valid queued work", %{jido: jido} do
    server = start_agent!(jido, Agent, error_policy: observe_errors())
    before = Server.snapshot(server)
    observer = self()
    abandoned_signal = change("abandoned", 100, true)

    caller =
      Task.async(fn ->
        Server.call(server, abandoned_signal,
          context: %{observer: observer, request: "abandoned context"}
        )
      end)

    assert_receive {:sdk_started, "abandoned", abandoned_worker, _, "abandoned context"}, 1_000
    monitor = Process.monitor(abandoned_worker)
    turn_id = Server.status(server).active.turn_id

    next_caller =
      Task.async(fn ->
        Server.call(server, change("next", 3, true), context: %{observer: observer})
      end)

    eventually(fn -> Server.status(server).admission.postponed == 1 end)
    assert :ok = Server.cancel_turn(server, turn_id)
    assert {:error, :cancelled} = Task.await(caller)
    assert_receive {:DOWN, ^monitor, :process, ^abandoned_worker, _}, 1_000
    assert_receive {:sdk_started, "next", next_worker, next_input, nil}, 1_000

    assert next_input == before.agent.state
    assert Server.snapshot(server) == before
    assert Effects.records(server) == []
    assert {:error, :stale_turn} = Server.cancel_turn(server, turn_id)

    # A late release has no live abandoned execution to complete. Do not
    # fabricate private Exec completion messages to test this public contract.
    send(abandoned_worker, {:sdk_release, "abandoned"})
    send(next_worker, {:sdk_release, "next"})
    assert {:ok, _} = Task.await(next_caller)
    eventually(fn -> Server.snapshot(server).state_version == 1 end)
    await_idle(server)
    assert Server.agent(server).state == %{count: 3, history: ["next"]}
    assert [%{label: "next"}] = Effects.records(server)
  end

  test "a caller timeout ends waiting without cancelling a started Turn", %{jido: jido} do
    server = start_agent!(jido, Agent)
    before = Server.snapshot(server)
    observer = self()
    command = change("late", 4, true)

    caller =
      Task.async(fn ->
        try do
          Server.call(server, command, timeout: 100, context: %{observer: observer})
        catch
          :exit, reason -> {:caller_exit, reason}
        end
      end)

    assert_receive {:sdk_started, "late", worker, _, nil}, 1_000
    assert {:caller_exit, {:timeout, _}} = Task.await(caller)
    assert Process.alive?(worker)
    assert Server.snapshot(server) == before
    assert Effects.records(server) == []

    send(worker, {:sdk_release, "late"})
    eventually(fn -> Server.snapshot(server).state_version == 1 end)
    await_idle(server)
    committed = Server.agent(server)
    assert committed.state == %{count: 4, history: ["late"]}

    assert [%{label: "late", snapshot: %{agent: ^committed, state_version: 1}}] =
             Effects.records(server)

    assert {:ok, next} =
             Server.call(server, change("after timeout", 1), context: %{observer: observer})

    await_idle(server)
    assert next.state == %{count: 5, history: ["late", "after timeout"]}
    assert Server.snapshot(server) == %{agent: next, state_version: 2}
    assert Enum.map(Effects.records(server), & &1.label) == ["late", "after timeout"]
  end

  defp change(label, amount, blocked? \\ false) do
    Agent.increment_signal!(amount, label, input: %{blocked?: blocked?})
  end
end
