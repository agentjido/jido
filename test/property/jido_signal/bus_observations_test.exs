Code.require_file("../support/fuzz.exs", __DIR__)
Code.require_file("../support/jido_signal/runtime.exs", __DIR__)

defmodule Jido.Signal.Property.BusObservationsTest do
  use ExUnit.Case, async: true
  import StreamData
  alias Jido.Trace
  alias Jido.Signal
  alias Jido.Signal.{Bus, Context}
  alias Jido.Test.Property.Fuzz
  alias Jido.Test.Property.Signal.Runtime

  def event(event, measurements, metadata, {owner, token, bus}) do
    if self() == bus, do: send(owner, {token, event, measurements, metadata})
  end

  for {suite, runs, bound} <- [{:property, 40, 4}, {:fuzz, 500, 12}] do
    @tag [
      {suite, true},
      fuzz_id: "bus_observations",
      max_runs: runs,
      max_run_time: if(suite == :fuzz, do: 300_000, else: 10_000),
      timeout: if(suite == :fuzz, do: 900_000, else: 90_000)
    ]
    test "#{suite}: Bus events follow subscription transitions", context do
      generator =
        list_of(member_of(~w(event.a event.b **.x.a)), min_length: 1, max_length: unquote(bound))

      examples = [["event.a"], ["event.a", "event.b", "**.x.a"]]

      Fuzz.check(
        "bus_observations",
        generator,
        Map.to_list(context) ++ [examples: examples],
        &check/1
      )
    end
  end

  defp check(types) do
    Runtime.with_bus([jido: :property_scope], fn %{bus: bus, token: token, name: name} ->
      handler = {__MODULE__, token}

      events =
        [
          [:jido, :signal, :bus, :publish],
          [:jido, :signal, :bus, :deliver],
          [:jido, :signal, :bus, :ack]
        ] ++ for last <- [:attached, :detached], do: [:jido, :signal, :bus, :subscription, last]

      :ok = :telemetry.attach_many(handler, events, &__MODULE__.event/4, {self(), token, bus})

      try do
        assert {:ok, "e"} = Bus.subscribe(bus, "**", subscription_id: "e")
        subscription(token, name, :attached, "e", false)
        assert {:ok, "d"} = Bus.subscribe(bus, "**", durable: "d", start_from: :origin)
        subscription(token, name, :attached, "d", true)
        trace = Trace.new()

        signals =
          for type <- types do
            signal = Signal.new!(type, %{"_probe" => token}, source: "/property")
            assert {:ok, signal} = Context.put_trace(signal, trace)
            signal
          end

        assert {:ok, records} = Bus.publish(bus, signals)

        for {signal, i} <- Enum.with_index(signals, 1) do
          assert_received {:signal, ^signal}
          delivery(token, name, "e", false, nil, signal, trace)

          if i == 1 do
            assert_received {:signal, "d", first}
            assert first.cursor == 1
            delivery(token, name, "d", true, 1, signal, trace)
          end
        end

        assert {^token, [:jido, :signal, :bus, :publish], measurements, metadata} =
                 Runtime.next(token)

        identity(metadata, name)
        assert measurements.count == length(types) and measurements.duration >= 0

        for record <- records do
          assert :ok = Bus.ack(bus, "d", record.cursor)

          assert {^token, [:jido, :signal, :bus, :ack], %{cursor: cursor}, metadata} =
                   Runtime.next(token)

          assert cursor == record.cursor
          identity(metadata, name)

          if record.cursor < length(records) do
            assert_received {:signal, "d", next}
            assert next.cursor == record.cursor + 1
            delivery(token, name, "d", true, next.cursor, next.signal, trace)
          end
        end

        owner = self()

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

          assert {:error, :subscription_in_use} =
                   Bus.subscribe(bus, "**", durable: "d", target: target)

          assert :ok = Bus.unsubscribe(bus, "d")
          subscription(token, name, :detached, "d", true)
          assert {:ok, "d"} = Bus.subscribe(bus, "**", durable: "d", target: target)
          subscription(token, name, :attached, "d", true)
          Jido.Test.Signal.Case.terminate_and_wait(bus, target)
          subscription(token, name, :detached, "d", true)
          assert {:ok, "d"} = Bus.subscribe(bus, "**", durable: "d")
          subscription(token, name, :attached, "d", true)
          assert :ok = Bus.unsubscribe(bus, "d")
          subscription(token, name, :detached, "d", true)
          assert :ok = Bus.unsubscribe(bus, "d")
          assert :ok = Bus.delete_subscription(bus, "d")
        after
          if Process.alive?(target), do: Process.exit(target, :kill)
        end

        assert :ok = Bus.unsubscribe(bus, "e")
        subscription(token, name, :detached, "e", false)
        refute_received {^token, _, _, _}
      after
        :telemetry.detach(handler)
      end
    end)

    ["records-#{length(types)}"]
  end

  defp subscription(token, name, event, id, durable?) do
    assert {^token, [:jido, :signal, :bus, :subscription, ^event], %{system_time: time}, metadata} =
             Runtime.next(token)

    assert is_integer(time)
    identity(metadata, name)
    assert metadata.subscription_id == id and metadata.durable == durable?
  end

  defp delivery(token, name, id, durable?, cursor, signal, trace) do
    assert {^token, [:jido, :signal, :bus, :deliver], _, metadata} = Runtime.next(token)
    identity(metadata, name)
    assert metadata.subscription_id == id and metadata.durable == durable?
    assert Map.get(metadata, :cursor) == cursor
    assert metadata.signal_id == signal.id and metadata.signal_type == signal.type
    assert metadata.jido_trace_id == trace.trace_id and metadata.jido_span_id == trace.span_id
  end

  defp identity(metadata, name) do
    assert metadata.bus_name == name
    assert metadata.bus_jido == :property_scope
    assert metadata.bus_registry == Jido.Signal.Registry
  end
end
