Code.require_file("../support/fuzz.exs", __DIR__)
Code.require_file("../support/jido_signal/runtime.exs", __DIR__)
Code.require_file("../support/jido_signal/model.exs", __DIR__)

defmodule Jido.Signal.Property.BusHistoriesTest do
  use ExUnit.Case, async: true
  import StreamData
  alias Jido.Signal
  alias Jido.Signal.Bus
  alias Jido.Signal.Codec
  alias Jido.Test.Property.Fuzz
  alias Jido.Test.Property.Signal.{Model, Runtime}

  for {suite, runs, bound} <- [{:property, 40, 12}, {:fuzz, 500, 40}] do
    @tag [
      {suite, true},
      fuzz_id: "bus_histories",
      max_runs: runs,
      max_run_time: if(suite == :fuzz, do: 300_000, else: 10_000),
      timeout: if(suite == :fuzz, do: 900_000, else: 90_000)
    ]
    test "#{suite}: Bus publication and durable state histories", context do
      command =
        fixed_map(%{
          "op" => member_of(~w(publish invalid ack wrong foreign detach attach delete ephemeral replay)),
          "types" => list_of(member_of(~w(event.a event.b audit **.x.a)), max_length: 3),
          "n" => integer(0..8)
        })

      generator = list_of(command, max_length: unquote(bound))

      examples = [
        [
          pub(~w(event.a audit event.b)),
          op("wrong"),
          op("foreign"),
          op("ack"),
          op("detach"),
          op("detach"),
          pub(~w(event.a)),
          op("attach"),
          op("ack"),
          op("ack"),
          op("ack")
        ],
        [
          pub(~w(event.a event.b)),
          op("delete"),
          op("attach"),
          op("ephemeral"),
          op("invalid"),
          op("replay")
        ],
        [
          pub(~w(event.a)),
          op("detach"),
          op("ack"),
          op("attach"),
          op("attach"),
          op("delete"),
          op("ack")
        ]
      ]

      Fuzz.check(
        "bus_histories",
        generator,
        Map.to_list(context) ++ [examples: examples],
        &check/1
      )
    end
  end

  defp op(name), do: %{"op" => name, "types" => [], "n" => 0}
  defp pub(types), do: Map.put(op("publish"), "types", types)

  defp check(commands) do
    Runtime.with_bus(fn runtime ->
      bus = runtime.bus
      assert {:ok, "ephemeral"} = Bus.subscribe(bus, "**", subscription_id: "ephemeral")

      assert {:ok, "durable"} =
               Bus.subscribe(bus, "event.**", durable: "durable", start_from: :origin)

      initial =
        Map.merge(runtime, %{
          log: [],
          ephemeral: true,
          exists: true,
          attached: true,
          cursor: 0,
          flight: nil
        })

      final =
        Enum.reduce(commands, initial, fn command, state ->
          next = step(command, state)
          assert {:ok, replayed} = Bus.replay(bus)
          assert project(replayed) == project(next.log)
          next
        end)

      refute_received {:signal, "durable", _}
      token = runtime.token
      refute_received {:signal, %Signal{data: %{"_probe" => ^token}}}
      death_case(final)
    end)

    ["commands-#{length(commands)}"]
  end

  defp step(%{"op" => "publish", "types" => types}, state) do
    signals =
      for {type, i} <- Enum.with_index(types),
          do: Signal.new!(type, %{"_probe" => state.token, "item" => i}, source: "/property")

    assert {:ok, records} = Bus.publish(state.bus, signals)

    expected_cursors = for {_signal, i} <- Enum.with_index(signals, length(state.log) + 1), do: i
    assert Enum.map(records, & &1.cursor) == expected_cursors
    assert Enum.map(records, & &1.signal) == signals

    if state.ephemeral,
      do: Enum.each(signals, fn signal -> assert_received {:signal, ^signal} end)

    next = %{state | log: state.log ++ records}
    deliver(next)
  end

  defp step(%{"op" => "invalid"}, state) do
    valid = Signal.new!("event.a", %{"_probe" => state.token}, source: "/property")
    assert {:error, _} = Bus.publish(state.bus, [valid, :invalid])
    assert {:error, :invalid_signals} = Bus.publish(state.bus, [valid | :tail])
    state
  end

  defp step(%{"op" => "ack"}, state) do
    result = Bus.ack(state.bus, "durable", state.flight || 0)

    expected =
      cond do
        not state.exists -> {:error, :subscription_not_found}
        not state.attached -> {:error, :not_subscription_owner}
        is_nil(state.flight) -> {:error, :no_record_in_flight}
        true -> :ok
      end

    assert result == expected
    if result == :ok, do: deliver(%{state | cursor: state.flight, flight: nil}), else: state
  end

  defp step(%{"op" => "wrong"}, state) do
    if state.exists and state.attached and state.flight do
      assert {:error, {:unexpected_cursor, state.flight}} ==
               Bus.ack(state.bus, "durable", state.flight + 1)
    end

    state
  end

  defp step(%{"op" => "foreign"}, state) do
    if state.exists do
      task = Task.async(fn -> Bus.ack(state.bus, "durable", state.flight || 0) end)

      try do
        assert Task.await(task) == {:error, :not_subscription_owner}
      after
        if Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill)
      end
    end

    state
  end

  defp step(%{"op" => "detach"}, state) do
    expected = if state.exists, do: :ok, else: {:error, :subscription_not_found}
    assert Bus.unsubscribe(state.bus, "durable") == expected
    %{state | attached: false, flight: nil}
  end

  defp step(%{"op" => "attach"}, state) do
    assert {:ok, "durable"} =
             Bus.subscribe(state.bus, "event.**", durable: "durable", start_from: :origin)

    next =
      if state.exists,
        do: %{state | attached: true},
        else: %{state | exists: true, attached: true, cursor: 0, flight: nil}

    deliver(next)
  end

  defp step(%{"op" => "delete"}, state) do
    expected = if state.exists, do: :ok, else: {:error, :subscription_not_found}
    assert Bus.delete_subscription(state.bus, "durable") == expected
    %{state | exists: false, attached: false, flight: nil}
  end

  defp step(%{"op" => "ephemeral"}, state) do
    if state.ephemeral do
      assert :ok = Bus.unsubscribe(state.bus, "ephemeral")
    else
      assert {:ok, "ephemeral"} = Bus.subscribe(state.bus, "**", subscription_id: "ephemeral")

      assert {:error, :subscription_already_exists} =
               Bus.subscribe(state.bus, "**", subscription_id: "ephemeral")
    end

    %{state | ephemeral: not state.ephemeral}
  end

  defp step(%{"op" => "replay", "n" => n}, state) do
    for path <- ["**", "event.*", "**.a"], limit <- [1, 2, :infinity] do
      expected = Enum.filter(state.log, &(&1.cursor > n and Model.matches?(&1.type, path)))
      expected = if limit == :infinity, do: expected, else: Enum.take(expected, limit)
      assert {:ok, found} = Bus.replay(state.bus, path, after: n, limit: limit)
      assert project(found) == project(expected)
    end

    state
  end

  defp deliver(%{exists: true, attached: true, flight: nil} = state) do
    case Enum.find(state.log, &(&1.cursor > state.cursor and Model.matches?(&1.type, "event.**"))) do
      nil ->
        state

      record ->
        assert_received {:signal, "durable", delivered}
        assert project([delivered]) == project([record])
        %{state | flight: record.cursor}
    end
  end

  defp deliver(state), do: state
  defp project(records), do: Enum.map(records, &{&1.cursor, &1.type, Codec.to_map(&1.signal)})

  defp death_case(state) do
    owner = self()
    token = state.token

    target =
      spawn(fn ->
        ref = Process.monitor(owner)
        send(owner, {token, :ready, self()})

        receive do
          {:DOWN, ^ref, :process, ^owner, _} -> :ok
        end
      end)

    try do
      assert_receive {^token, :ready, ^target}, 5_000

      assert {:ok, "death"} =
               Bus.subscribe(state.bus, "event.**",
                 durable: "death",
                 target: target,
                 start_from: :origin
               )

      assert {:ok, "ephemeral-death"} =
               Bus.subscribe(state.bus, "**", subscription_id: "ephemeral-death", target: target)

      Jido.Test.Signal.Case.terminate_and_wait(state.bus, target)
      assert {:error, :subscription_not_found} = Bus.unsubscribe(state.bus, "ephemeral-death")

      assert {:ok, "death"} =
               Bus.subscribe(state.bus, "event.**", durable: "death", start_from: :origin)

      case Enum.find(state.log, &Model.matches?(&1.type, "event.**")) do
        nil ->
          refute_received {:signal, "death", _}

        record ->
          assert_received {:signal, "death", delivered}
          assert project([delivered]) == project([record])
      end

      assert {:ok, "dead-ephemeral"} =
               Bus.subscribe(state.bus, "**", subscription_id: "dead-ephemeral")

      assert :ok = Bus.unsubscribe(state.bus, "dead-ephemeral")
    after
      if Process.alive?(target), do: Process.exit(target, :kill)
    end
  end
end
