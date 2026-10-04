defmodule JidoTest.Examples.Runtime.BusDeliveryFixture do
  @moduledoc false

  use Jido.Agent, name: "test_bus_delivery"

  agent do
    schema Zoi.object(%{
             seen: Zoi.list(Zoi.string()) |> Zoi.default([]),
             values: Zoi.list(Zoi.integer()) |> Zoi.default([])
           })

    plugin Jido.Plugin.Bus.Manager, config: [name: :example_commands]

    plugin Jido.Plugin.Bus.Client,
      config: [
        bus: :example_commands,
        path: "examples.runtime.bus_delivery.**",
        durable: "test-consumer",
        start_from: :origin,
        retry_delay_ms: 10
      ]
  end

  routes do
    signal_source "/test/bus_delivery"

    route "examples.runtime.bus_delivery.record", as: :record do
      action %{value: value}, schema: Zoi.object(%{value: Zoi.integer()}), context: context do
        context.plugin_inputs[JidoTest.FeatureObserver].runtime.on_delivery.(%{value: value})
        state = context.agent_state

        if context.signal.id in state.seen do
          {:ok, state}
        else
          {:ok,
           %{
             state
             | seen: state.seen ++ [context.signal.id],
               values: state.values ++ [value]
           }}
        end
      end
    end
  end
end

defmodule JidoTest.Examples.Runtime.BusDeliveryTest do
  use JidoTest.FeatureSDKCase
  @moduletag group: :runtime
  alias Jido.Examples.BusDelivery
  alias Jido.Plugin.Bus.{Client, Manager}
  alias Jido.Signal.Bus
  alias JidoTest.Examples.Runtime.BusDeliveryFixture

  test "durable delivery waits for a commit before it sends the next record", %{jido: jido} do
    {:ok, agent} = Jido.start_agent(jido, observed(BusDeliveryFixture, :on_delivery))
    bus = owned_bus(jido, agent)

    {:ok, command_signal_1} = BusDeliveryFixture.record_signal(%{value: 1})
    {:ok, command_signal_2} = BusDeliveryFixture.record_signal(%{value: 2})

    assert {:ok, [_, _]} =
             Bus.publish(bus, [command_signal_1, command_signal_2])

    assert_receive {:feature_work, first, %{value: 1}}, 1000
    assert state(agent).values == []
    assert Server.snapshot(agent).state_version == 0
    refute_received {:feature_work, _, %{value: 2}}
    send(first, :release)
    assert_receive {:feature_work, second, %{value: 2}}, 1000
    assert state(agent).values == [1]
    send(second, :release)
    eventually(fn -> state(agent).values == [1, 2] end)
    assert Server.snapshot(agent).state_version == 2
  end

  test "a failed Turn retries the same record before later input", %{jido: jido} do
    {:ok, agent} =
      Jido.start_agent(jido, observed(BusDeliveryFixture, :on_delivery), error_policy: :log_only)

    bus = owned_bus(jido, agent)

    {:ok, command_signal_3} = BusDeliveryFixture.record_signal(%{value: 3})
    {:ok, command_signal_4} = BusDeliveryFixture.record_signal(%{value: 4})

    assert {:ok, [_, _]} =
             Bus.publish(bus, [command_signal_3, command_signal_4])

    assert_receive {:feature_work, first, %{value: 3}}, 1000
    send(first, :fail)
    assert_receive {:feature_work, retry, %{value: 3}}, 1000
    assert state(agent).values == []
    assert Server.snapshot(agent).state_version == 0
    send(retry, :release)
    assert_receive {:feature_work, next, %{value: 4}}, 1000
    send(next, :release)
    eventually(fn -> state(agent).values == [3, 4] end)
  end

  test "a restarted Client resumes the subscription and duplicate IDs keep one value", %{
    jido: jido
  } do
    agent = start_agent!(jido, BusDelivery)
    bus = owned_bus(jido, agent)
    {:ok, event} = BusDelivery.record_signal(%{value: 7})
    assert {:ok, [_]} = Bus.publish(bus, [event])
    eventually(fn -> state(agent).values == ~c"\a" end)
    old = Server.children(agent)[{:plugin, Client}].pid
    Process.exit(old, :kill)
    eventually(fn -> Server.children(agent)[{:plugin, Client}].pid != old end)

    {:ok, command_signal_5} = BusDelivery.record_signal(%{value: 9})

    assert {:ok, [_, _]} =
             Bus.publish(bus, [event, command_signal_5])

    eventually(fn -> state(agent).values == ~c"\a\t" end)
    assert length(state(agent).seen) == 2
    # Duplicate acknowledgement is a successful unchanged-state Turn.
    assert Server.snapshot(agent).state_version >= 3
  end

  test "normal input outside the subscription path does not enter the Agent", %{jido: jido} do
    agent = start_agent!(jido, BusDelivery)
    bus = owned_bus(jido, agent)

    {:ok, command_signal_6} = BusDelivery.record_signal(%{value: 5})

    assert {:ok, [_, _]} =
             Bus.publish(bus, [signal("unrelated.record", %{value: 100}), command_signal_6])

    eventually(fn -> state(agent).values == [5] end)
    assert Server.snapshot(agent).state_version == 1
    children = Server.children(agent)
    client = children[{:plugin, Client}].pid
    manager = children[{:plugin, Manager}].pid
    client_ref = Process.monitor(client)
    manager_ref = Process.monitor(manager)
    assert :ok = Jido.stop_agent(jido, agent)
    assert_receive {:DOWN, ^client_ref, :process, ^client, _}, 1000
    assert_receive {:DOWN, ^manager_ref, :process, ^manager, _}, 1000
    eventually(fn -> Bus.whereis(:example_commands, jido: jido) == {:error, :not_found} end)
  end

  defp owned_bus(jido, agent) do
    assert :ok = Server.await_ready(agent)
    assert {:ok, bus} = Bus.whereis(:example_commands, jido: jido)

    assert %{
             {:plugin, Manager} => %{pid: ^bus},
             {:plugin, Client} => %{pid: client}
           } = Server.children(agent)

    assert is_pid(client)
    bus
  end
end
