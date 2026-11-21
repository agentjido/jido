Code.require_file("timer.ex", __DIR__)
Code.require_file("burst_buncher.ex", __DIR__)

defmodule Jido.Examples.Runtime.BurstBuncherTest do
  use Jido.Test.Agent.Case
  @moduletag :integration

  @moduletag group: :runtime
  @moduletag complexity: 2
  alias Jido.Examples.BurstBuncher

  test "maximum size flushes one ordered batch after commit", %{jido: jido} do
    buncher = start_buncher(jido, max_size: 2, flush_delay_ms: 1000)

    {:ok, route_signal_1} = BurstBuncher.add_item_signal(%{item_id: "item-1", item: %{value: 1}})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(buncher, route_signal_1, [])

      assert turn_result.status in [:committed, :waiting]
      first = Jido.AgentServer.snapshot(buncher).agent
    )

    assert first.state.buffer == [%{id: "item-1", value: %{value: 1}}]

    {:ok, route_signal_2} = BurstBuncher.add_item_signal(%{item_id: "item-2", item: %{value: 2}})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(buncher, route_signal_2, [])

      assert turn_result.status in [:committed, :waiting]
      second = Jido.AgentServer.snapshot(buncher).agent
    )

    assert second.state.buffer == []
    assert second.state.last_flush_reason == :size

    assert_receive {:signal,
                    %Jido.Signal{
                      type: "examples.runtime.burst_buncher.batch",
                      data: %{
                        batch_id: "batch-1",
                        reason: :size,
                        items: [
                          %{id: "item-1", value: %{value: 1}},
                          %{id: "item-2", value: %{value: 2}}
                        ]
                      }
                    }},
                   500

    assert agent_result(buncher).agent_revision == 2
  end

  test "stale timer generations cannot drain a newer batch", %{jido: jido} do
    buncher = start_buncher(jido, max_size: 3, flush_delay_ms: 1000)

    {:ok, route_signal_3} = BurstBuncher.add_item_signal(%{item_id: "item-1", item: :first})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(buncher, route_signal_3, [])

      assert turn_result.status in [:committed, :waiting]
      first = Jido.AgentServer.snapshot(buncher).agent
    )

    assert first.state.timer_generation == 1

    {:ok, route_signal_4} = BurstBuncher.add_item_signal(%{item_id: "item-2", item: :second})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(buncher, route_signal_4, [])

      assert turn_result.status in [:committed, :waiting]
      second = Jido.AgentServer.snapshot(buncher).agent
    )

    assert second.state.timer_generation == 2

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(buncher, BurstBuncher.timer_flush_signal!(1))

      assert turn_result.status in [:committed, :waiting]
      unchanged = Jido.AgentServer.snapshot(buncher).agent
    )

    assert Enum.map(unchanged.state.buffer, & &1.id) == ["item-1", "item-2"]

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(buncher, BurstBuncher.timer_flush_signal!(2))

      assert turn_result.status in [:committed, :waiting]
      flushed = Jido.AgentServer.snapshot(buncher).agent
    )

    assert flushed.state.buffer == []

    assert_receive {:signal,
                    %Jido.Signal{
                      type: "examples.runtime.burst_buncher.batch",
                      data: %{batch_id: "batch-1"}
                    }},
                   500
  end

  test "a duplicate item ID does not enter the batch twice", %{jido: jido} do
    buncher = start_buncher(jido, max_size: 2, flush_delay_ms: 1000)

    {:ok, duplicate} =
      BurstBuncher.add_item_signal(%{item_id: "item-1", item: :first})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(buncher, duplicate)

      assert turn_result.status in [:committed, :waiting]
      _agent = Jido.AgentServer.snapshot(buncher).agent
    )

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(buncher, duplicate)

      assert turn_result.status in [:committed, :waiting]
      unchanged = Jido.AgentServer.snapshot(buncher).agent
    )

    assert Enum.map(unchanged.state.buffer, & &1.id) == ["item-1"]

    {:ok, route_signal_5} = BurstBuncher.add_item_signal(%{item_id: "item-2", item: :second})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(buncher, route_signal_5, [])

      assert turn_result.status in [:committed, :waiting]
      _agent = Jido.AgentServer.snapshot(buncher).agent
    )

    assert_receive {:signal,
                    %Jido.Signal{
                      type: "examples.runtime.burst_buncher.batch",
                      data: %{items: items}
                    }},
                   500

    assert Enum.map(items, & &1.id) == ["item-1", "item-2"]
  end

  defp start_buncher(jido, state) do
    start_agent!(jido, BurstBuncher,
      state: Map.new(state),
      default_dispatch: {:pid, target: self()}
    )
  end

  test "the timer flushes a partial batch without another command", %{jido: jido} do
    buncher = start_buncher(jido, max_size: 3, flush_delay_ms: 10)

    {:ok, route_signal_6} = BurstBuncher.add_item_signal(%{item_id: "item", item: :value})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(buncher, route_signal_6, [])

      assert turn_result.status in [:committed, :waiting]
    )

    assert_receive {:signal,
                    %Jido.Signal{
                      type: "examples.runtime.burst_buncher.batch",
                      data: %{reason: :timeout, items: [%{id: "item"}]}
                    }},
                   1000

    assert Jido.AgentServer.snapshot(buncher).agent.state.buffer == []
  end
end
