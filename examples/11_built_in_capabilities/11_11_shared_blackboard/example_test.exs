Code.require_file("example.ex", __DIR__)

defmodule Jido.Examples.SharedBlackboardTest do
  use Jido.Test.Case, async: false

  alias Jido.{AgentServer, Blackboard, Statechart}
  alias Jido.Examples.SharedBlackboard.{Counter, Desk}

  @moduletag :integration

  test "one counter records an inventory count and another reads it", %{jido: jido} do
    {desk, [{_first_id, first}, {_second_id, second}]} = start_desk(jido)
    assert {:ok, %{status: :committed}} = Statechart.initialize(first, %{"request_id" => "count-12"})
    assert {:ok, %{status: :committed}} = AgentServer.call(first, Counter.read_signal!(%{}))

    unrelated = signal("jido.blackboard.patch.result", %{"request_id" => "other", "status" => "ok"})
    assert {:ok, %{status: :committed}} = AgentServer.call(first, unrelated)
    assert %{state: "waiting"} = Statechart.session(first)

    assert {:ok, %{status: :committed}} =
             AgentServer.call(first, Counter.count_signal!(%{count: 12, request_id: "count-12"}))

    assert_eventually(match?(%{state: "recorded"}, Statechart.session(first)))

    assert {:ok, %{status: :committed}} = AgentServer.call(second, Counter.read_signal!(%{}))
    assert AgentServer.snapshot(second).agent.state.observed_count == 12

    assert :ok = Jido.stop_agent(jido, desk)
    assert {:error, :unavailable} = Blackboard.read(jido, "inventory")
  end

  test "a stale update sends the counter back to read, even after the counter restarts", %{jido: jido} do
    {desk, [{first_id, first}, {_second_id, second}]} = start_desk(jido)

    for {counter, request_id} <- [{first, "first"}, {second, "second"}] do
      assert {:ok, %{status: :committed}} = Statechart.initialize(counter, %{"request_id" => request_id})
      assert {:ok, %{status: :committed}} = AgentServer.call(counter, Counter.read_signal!(%{}))
    end

    assert AgentServer.snapshot(first).agent.state.revision == AgentServer.snapshot(second).agent.state.revision

    requests = [{first, 12, "first"}, {second, 15, "second"}]

    requests
    |> Task.async_stream(fn {counter, count, request_id} ->
      AgentServer.call(counter, Counter.count_signal!(%{count: count, request_id: request_id}))
    end)
    |> Enum.each(fn result -> assert {:ok, {:ok, %{status: :committed}}} = result end)

    assert_eventually(
      Enum.sort([Statechart.session(first).state, Statechart.session(second).state]) ==
        ["read_again", "recorded"]
    )

    {count, losing_counter} = if Statechart.session(first).state == "recorded", do: {12, second}, else: {15, first}
    assert {:ok, %{status: :committed}} = AgentServer.call(losing_counter, Counter.read_signal!(%{}))
    assert AgentServer.snapshot(losing_counter).agent.state.observed_count == count

    monitor = Process.monitor(first)
    Process.exit(first, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^first, :killed}

    replacement =
      eventually(fn ->
        case Jido.whereis_agent(jido, first_id) do
          pid when is_pid(pid) and pid != first -> pid
          _other -> nil
        end
      end)

    assert is_pid(replacement)
    assert :ok = AgentServer.await_ready(replacement)
    assert {:ok, %{status: :committed}} = AgentServer.call(replacement, Counter.read_signal!(%{}))
    assert AgentServer.snapshot(replacement).agent.state.observed_count == count

    assert {:ok, %{revision: old_revision}} = Blackboard.read(jido, "inventory")
    assert :ok = Jido.stop_agent(jido, desk)
    {new_desk, _counters} = start_desk(jido)

    assert {:error, :conflict} = Blackboard.patch(jido, "inventory", old_revision, %{"bin-a" => 15})
    assert {:ok, %{values: %{"bin-a" => 0}}} = Blackboard.read(jido, "inventory")
    assert :ok = Jido.stop_agent(jido, new_desk)
  end

  defp start_desk(jido) do
    assert {:ok, desk} = Jido.start_agent(jido, Desk, id: unique_id("inventory-desk"))
    assert :ok = AgentServer.await_ready(desk)
    assert [_, _] = counters = Enum.reject(Jido.list_agents(jido), fn {_id, pid} -> pid == desk end)
    {desk, counters}
  end
end
