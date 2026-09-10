defmodule JidoTest.Examples.Runtime.BusDeliveryFixture do
  @moduledoc false

  use Jido.Agent, name: "test_bus_delivery"

  agent do
    schema Zoi.object(%{
             seen: Zoi.list(Zoi.string()) |> Zoi.default([]),
             values: Zoi.list(Zoi.integer()) |> Zoi.default([])
           })

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

    route "examples.runtime.bus_delivery.record" do
      action %{value: value}, schema: Zoi.object(%{value: Zoi.integer()}), context: context do
        context.on_delivery.(%{value: value})
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

      define :record, args: [:value]
    end
  end
end

defmodule JidoTest.Examples.Runtime.BusDeliveryTest do
  use JidoTest.FeatureSDKCase
  @moduletag group: :runtime
  alias Jido.Examples.BusDelivery
  alias Jido.Plugin.Bus.Client
  alias Jido.Signal.Bus
  alias JidoTest.Examples.Runtime.BusDeliveryFixture

  test "durable delivery waits for a commit before it sends the next record", %{jido: jido} do
    bus = start_supervised!({Bus, name: :example_commands, jido: jido})
    {:ok, agent} = Jido.start_agent(jido, observed(BusDeliveryFixture, :on_delivery))

    assert {:ok, [_, _]} =
             Bus.publish(bus, [
               BusDeliveryFixture.record_signal!(1),
               BusDeliveryFixture.record_signal!(2)
             ])

    assert_receive {:feature_work, first, %{value: 1}}, 1_000
    assert state(agent).values == []
    assert Server.snapshot(agent).state_version == 0
    refute_received {:feature_work, _, %{value: 2}}
    send(first, :release)
    assert_receive {:feature_work, second, %{value: 2}}, 1_000
    assert state(agent).values == [1]
    send(second, :release)
    eventually(fn -> state(agent).values == [1, 2] end)
    assert Server.snapshot(agent).state_version == 2
  end

  test "a failed Turn retries the same record before later input", %{jido: jido} do
    bus = start_supervised!({Bus, name: :example_commands, jido: jido})

    {:ok, agent} =
      Jido.start_agent(jido, observed(BusDeliveryFixture, :on_delivery), error_policy: :log_only)

    assert {:ok, [_, _]} =
             Bus.publish(bus, [
               BusDeliveryFixture.record_signal!(3),
               BusDeliveryFixture.record_signal!(4)
             ])

    assert_receive {:feature_work, first, %{value: 3}}, 1_000
    send(first, :fail)
    assert_receive {:feature_work, retry, %{value: 3}}, 1_000
    assert state(agent).values == []
    assert Server.snapshot(agent).state_version == 0
    send(retry, :release)
    assert_receive {:feature_work, next, %{value: 4}}, 1_000
    send(next, :release)
    eventually(fn -> state(agent).values == [3, 4] end)
  end

  test "a restarted Client resumes the subscription and duplicate IDs keep one value", %{
    jido: jido
  } do
    bus = start_supervised!({Bus, name: :example_commands, jido: jido})
    agent = start_agent!(jido, BusDelivery)
    event = BusDelivery.record_signal!(7)
    assert {:ok, [_]} = Bus.publish(bus, [event])
    eventually(fn -> state(agent).values == [7] end)
    old = Server.children(agent)[{:plugin, Client}].pid
    Process.exit(old, :kill)
    eventually(fn -> Server.children(agent)[{:plugin, Client}].pid != old end)
    assert {:ok, [_, _]} = Bus.publish(bus, [event, BusDelivery.record_signal!(9)])
    eventually(fn -> state(agent).values == [7, 9] end)
    assert length(state(agent).seen) == 2
    # Duplicate acknowledgement is a successful unchanged-state Turn.
    assert Server.snapshot(agent).state_version >= 3
  end

  test "normal input outside the subscription path does not enter the Agent", %{jido: jido} do
    bus = start_supervised!({Bus, name: :example_commands, jido: jido})
    agent = start_agent!(jido, BusDelivery)

    assert {:ok, [_, _]} =
             Bus.publish(bus, [
               signal("unrelated.record", %{value: 100}),
               BusDelivery.record_signal!(5)
             ])

    eventually(fn -> state(agent).values == [5] end)
    assert Server.snapshot(agent).state_version == 1
    runtime = Server.children(agent)[{:plugin, Client}].pid
    ref = Process.monitor(runtime)
    assert :ok = Jido.stop_agent(jido, agent)
    assert_receive {:DOWN, ^ref, :process, ^runtime, _}, 1_000
  end
end
