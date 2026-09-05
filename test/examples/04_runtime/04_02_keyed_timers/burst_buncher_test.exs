defmodule JidoTest.Examples.Runtime.BurstBuncherTest do
  use JidoTest.AgentCase
  @moduletag :integration

  @moduletag group: :runtime
  @moduletag complexity: 2

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.BurstBuncher
  alias Jido.Examples.BurstBuncher.Timer
  alias Jido.Examples.BurstBuncher.Timer.Runtime

  test "maximum size flushes one ordered batch after commit", %{jido: jido} do
    buncher = start_buncher(jido, max_size: 2, flush_delay_ms: 1_000)

    assert {:ok, first} = BurstBuncher.add_item(buncher, "item-1", %{value: 1})
    assert first.state.buffer == [%{id: "item-1", value: %{value: 1}}]

    assert {:ok, second} = BurstBuncher.add_item(buncher, "item-2", %{value: 2})
    assert second.state.buffer == []
    assert second.state.last_flush_reason == :size

    assert_receive {:signal,
                    %Jido.Signal{
                      type: "examples.buncher.batch",
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

    assert agent_result(buncher).state_version == 2
  end

  test "a later item replaces the pending timeout", %{jido: jido} do
    buncher = start_buncher(jido, max_size: 3, flush_delay_ms: 1_000)

    assert {:ok, _agent} = BurstBuncher.add_item(buncher, "item-1", :first)
    assert {:ok, _agent} = BurstBuncher.add_item(buncher, "item-2", :second)

    # The call returns at commit; the replacement timer is installed by dispatch.
    eventually(fn -> Server.status(buncher).phase == :idle end)
    runtime = Server.children(buncher)[{:plugin, Timer}].pid
    assert :ok = Runtime.fire(runtime, :flush)
    assert {:error, :not_found} = Runtime.fire(runtime, :flush)

    assert_receive {:signal,
                    %Jido.Signal{
                      type: "examples.buncher.batch",
                      data: %{reason: :timeout, items: items}
                    }},
                   500

    assert Enum.map(items, & &1.id) == ["item-1", "item-2"]

    assert %{state: %{buffer: [], last_flush_reason: :timeout}, state_version: 3} =
             agent_result(buncher)
  end

  test "stale timer generations cannot drain a newer batch", %{jido: jido} do
    buncher = start_buncher(jido, max_size: 3, flush_delay_ms: 1_000)

    assert {:ok, first} = BurstBuncher.add_item(buncher, "item-1", :first)
    assert first.state.timer_generation == 1

    assert {:ok, second} = BurstBuncher.add_item(buncher, "item-2", :second)
    assert second.state.timer_generation == 2

    assert {:ok, unchanged} = Server.call(buncher, BurstBuncher.timer_flush_signal!(1))
    assert Enum.map(unchanged.state.buffer, & &1.id) == ["item-1", "item-2"]

    assert {:ok, flushed} = Server.call(buncher, BurstBuncher.timer_flush_signal!(2))
    assert flushed.state.buffer == []

    assert_receive {:signal,
                    %Jido.Signal{type: "examples.buncher.batch", data: %{batch_id: "batch-1"}}},
                   500
  end

  test "a duplicate item ID does not enter the batch twice", %{jido: jido} do
    buncher = start_buncher(jido, max_size: 2, flush_delay_ms: 1_000)
    duplicate = BurstBuncher.add_item_signal!("item-1", :first)

    assert {:ok, _agent} = Server.call(buncher, duplicate)
    assert {:ok, unchanged} = Server.call(buncher, duplicate)
    assert Enum.map(unchanged.state.buffer, & &1.id) == ["item-1"]

    assert {:ok, _agent} = BurstBuncher.add_item(buncher, "item-2", :second)

    assert_receive {:signal, %Jido.Signal{type: "examples.buncher.batch", data: %{items: items}}},
                   500

    assert Enum.map(items, & &1.id) == ["item-1", "item-2"]
  end

  defp start_buncher(jido, state) do
    start_agent!(jido, BurstBuncher,
      initial_state: Map.new(state),
      default_dispatch: {:pid, target: self()}
    )
  end
end
