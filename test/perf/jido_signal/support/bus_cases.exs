defmodule Jido.Test.Perf.Signal.RejectingStore do
  @moduledoc false
  @behaviour Jido.Signal.Bus.Store
  alias Jido.Signal.Bus.Store.Memory
  @impl true
  defdelegate init(opts), to: Memory
  @impl true
  def append(_records, _state), do: {:error, :benchmark_store_failure}
  @impl true
  defdelegate read(opts, state), to: Memory
  @impl true
  defdelegate latest_cursor(state), to: Memory
  @impl true
  defdelegate list_subscriptions(state), to: Memory
  @impl true
  defdelegate put_subscription(subscription, state), to: Memory
  @impl true
  defdelegate delete_subscription(id, state), to: Memory
end

defmodule Jido.Test.Perf.Signal.BusCases do
  @moduledoc false
  alias Jido.Signal.{Bus, Dispatch}
  alias Jido.Test.Perf.Signal.{Helpers, RejectingStore}
  import Helpers, only: [stateful: 6, expect!: 2]

  def workloads(size) do
    fanout(size) ++
      backlog(size) ++
      [concurrent(size), sustained(size)] ++
      replay(size) ++ [reconnect(size)] ++ errors(size) ++ dispatch_errors()
  end

  defp fanout(size) do
    events = Helpers.events(size)

    [
      stateful(
        "bus/fanout_processes",
        events,
        fn state ->
          state = Map.put(state, :bus, Helpers.bus(state, size + 1))
          consumers = for index <- 1..size, do: consumer(state, index, size, false)
          Map.put(state, :consumers, consumers)
        end,
        fn state ->
          {:ok, records} = Bus.publish(state.bus, events)
          await_consumers(state)
          records
        end,
        fn records, state ->
          Helpers.records(records, events)
          drain_consumers(state, events)
        end,
        %{consumers: size, records: size}
      )
    ]
  end

  defp backlog(size) do
    events = Helpers.events(size * 16)

    for mode <- [:publish, :drain] do
      stateful(
        "bus/backlog_#{mode}",
        events,
        fn state ->
          state = Map.put(state, :bus, Helpers.bus(state, length(events) + 1))
          pid = consumer(state, 1, length(events), true)
          if mode == :drain, do: publish_batches(state.bus, events, size)
          Map.put(state, :consumers, [pid])
        end,
        fn state ->
          if mode == :publish do
            publish_batches(state.bus, events, size)
          else
            Enum.each(state.consumers, &send(&1, :consume))
            await_consumers(state)
          end
        end,
        fn result, state ->
          if mode == :publish do
            Helpers.records(result, events)
            Enum.each(state.consumers, &send(&1, :consume))
            await_consumers(state)
          else
            expect!(result, :ok)
          end

          drain_consumers(state, events)
        end,
        %{consumers: 1, records: length(events), batch_size: size, rounds: 16}
      )
    end
  end

  defp concurrent(size) do
    producer_count = min(size, 8)

    batches =
      for index <- 1..producer_count do
        events =
          for event <- Helpers.events(size * 4), do: %{event | id: "producer#{index}:#{event.id}"}

        {index, events}
      end

    all_events = Enum.flat_map(batches, &elem(&1, 1))

    stateful(
      "bus/concurrent_publish",
      all_events,
      fn state ->
        state = Map.put(state, :bus, Helpers.bus(state, length(all_events) + 1))
        consumers = for index <- 1..2, do: consumer(state, index, length(all_events), false)

        producers =
          for {index, events} <- batches do
            pid =
              Helpers.worker(state, fn ->
                send(state.owner, {state.tag, :producer_ready, index, :ok})
                receive do: (:publish -> :ok)
                records = publish_batches(state.bus, events, size)
                send(state.owner, {state.tag, :published, index, records})
                Helpers.hold()
              end)

            :ok = Helpers.wait(state.tag, :producer_ready, index)
            {index, pid}
          end

        Map.merge(state, %{consumers: consumers, producers: producers})
      end,
      fn state ->
        Enum.each(state.producers, fn {_, pid} -> send(pid, :publish) end)

        results =
          for {index, _} <- state.producers,
              do: {index, Helpers.wait(state.tag, :published, index)}

        await_consumers(state)
        results
      end,
      fn results, state ->
        for {index, records} <- results do
          expect!(Enum.map(records, & &1.signal), batches |> List.keyfind(index, 0) |> elem(1))
          cursors = Enum.map(records, & &1.cursor)
          expect!(cursors, Enum.sort(cursors))
        end

        records = results |> Enum.flat_map(&elem(&1, 1)) |> Enum.sort_by(& &1.cursor)
        expect!(Enum.map(records, & &1.cursor), Enum.to_list(1..length(all_events)))

        expect!(
          Enum.sort(Enum.map(records, & &1.signal.id)),
          Enum.sort(Enum.map(all_events, & &1.id))
        )

        expect!(Bus.replay(state.bus), {:ok, records})
        drain_consumers(state, Enum.map(records, & &1.signal))
      end,
      %{
        publishers: producer_count,
        consumers: 2,
        records: length(all_events),
        rounds: 4,
        batch_size: size
      }
    )
  end

  defp sustained(size) do
    capacity = size * 16
    initial = Helpers.events(capacity)
    events = for event <- Helpers.events(size * 64), do: %{event | id: "next:#{event.id}"}

    stateful(
      "bus/sustained_publish",
      events,
      fn state ->
        bus = Helpers.bus(state, capacity)
        {:ok, _} = Bus.publish(bus, initial)
        Map.put(state, :bus, bus)
      end,
      fn state -> publish_batches(state.bus, events, size) end,
      fn records, state ->
        Helpers.records(records, events, capacity + 1)
        {:ok, retained} = Bus.replay(state.bus)
        Helpers.records(retained, Enum.take(events, -capacity), length(events) + 1)
      end,
      %{records: length(events), log_capacity: capacity, rounds: 64, batch_size: size}
    )
  end

  defp replay(size) do
    events = Helpers.events(size * 256)
    count = length(events)

    for {name, path, opts, expected, cursor} <- [
          {"large_replay", "bench.**", [], events, 1},
          {"large_replay_filtered", "bench.item#{count}.*", [limit: 1], [List.last(events)], count},
          {"large_replay_cursor", "bench.**", [after: count - size, limit: size], Enum.take(events, -size),
           count - size + 1}
        ] do
      stateful(
        "bus/#{name}",
        events,
        fn state ->
          bus = Helpers.bus(state, count)
          {:ok, _} = Bus.publish(bus, events)
          Map.put(state, :bus, bus)
        end,
        fn state -> Bus.replay(state.bus, path, opts) end,
        fn {:ok, records}, _ -> Helpers.records(records, expected, cursor) end,
        %{records: count, returned_records: length(expected)}
      )
    end
  end

  defp reconnect(size) do
    events = Helpers.events(size)
    {online, offline} = Enum.split(events, div(size, 2))

    stateful(
      "bus/durable_reconnect",
      events,
      fn state ->
        state = Map.put(state, :bus, Helpers.bus(state, size))

        old =
          Helpers.worker(state, fn ->
            {:ok, "recover"} = Bus.subscribe(state.bus, "bench.**", durable: "recover")
            send(state.owner, {state.tag, :attached, 1, :ok})

            receive do
              {:signal, "recover", record} -> send(state.owner, {state.tag, :first, 1, record})
            end

            Helpers.hold()
          end)

        :ok = Helpers.wait(state.tag, :attached, 1)
        {:ok, _} = Bus.publish(state.bus, online)
        first = Helpers.wait(state.tag, :first, 1)
        Helpers.terminate(state, old)
        {:ok, _} = Bus.publish(state.bus, offline)
        Map.put(state, :first, first)
      end,
      fn state ->
        {:ok, "recover"} = Bus.subscribe(state.bus, "bench.**", durable: "recover")

        for _ <- events do
          receive do
            {:signal, "recover", record} ->
              # Subscribe/ack replies are barriers for Bus sends to this caller.
              Helpers.empty_mailbox!()
              :ok = Bus.ack(state.bus, "recover", record.cursor)
              record
          after
            5_000 -> raise "reconnected durable delivery missing"
          end
        end
      end,
      fn records, state ->
        Helpers.records(records, events)
        expect!(hd(records), state.first)
        Helpers.empty_mailbox!()
      end,
      %{records: size, consumers: 2, offline_records: length(offline)}
    )
  end

  defp errors(size) do
    events = Helpers.events(size)

    for mode <- [:invalid_signal, :store_full, :store_failure] do
      stateful(
        "bus/#{mode}",
        events,
        fn state ->
          opts = if mode == :store_failure, do: [store: RejectingStore], else: []
          bus = Helpers.bus(state, size, opts)
          {:ok, _} = Bus.subscribe(bus, "bench.**")

          if mode == :store_full do
            {:ok, "blocked"} = Bus.subscribe(bus, "bench.**", durable: "blocked")
            {:ok, _} = Bus.publish(bus, events)

            for event <- events do
              receive do
                {:signal, ^event} -> :ok
              after
                0 -> raise "initial delivery missing"
              end
            end

            receive do
              {:signal, "blocked", record} -> expect!(record.cursor, 1)
            after
              0 -> raise "initial durable delivery missing"
            end
          end

          Helpers.empty_mailbox!()
          Map.put(state, :bus, bus)
        end,
        fn state ->
          input =
            if mode == :invalid_signal, do: [%{hd(events) | source: 123}], else: [hd(events)]

          Bus.publish(state.bus, input)
        end,
        fn result, state ->
          check_error(mode, result)
          {:ok, retained} = Bus.replay(state.bus)

          if mode == :store_full,
            do: Helpers.records(retained, events),
            else: expect!(retained, [])

          Helpers.empty_mailbox!()
        end,
        %{records: size}
      )
    end
  end

  defp check_error(
         :invalid_signal,
         {:error, %Jido.Error.ValidationError{details: details}}
       ),
       do: expect!(details.index, 0)

  defp check_error(:store_full, result),
    do: expect!(result, {:error, {:store_error, :append, {:store_full, ["blocked"]}}})

  defp check_error(:store_failure, result),
    do: expect!(result, {:error, {:store_error, :append, :benchmark_store_failure}})

  defp dispatch_errors do
    [event] = Helpers.events(1)

    for mode <- [:dead_pid, :timeout] do
      stateful(
        "dispatch/#{mode}",
        event,
        fn state ->
          pid =
            Helpers.worker(state, fn ->
              send(state.owner, {state.tag, :ready, 1, :ok})

              if mode == :timeout do
                receive do
                  {:"$gen_call", _from, _message} ->
                    send(state.owner, {state.tag, :called, 1, :ok})
                end

                Helpers.hold()
              end
            end)

          :ok = Helpers.wait(state.tag, :ready, 1)

          if mode == :dead_pid do
            ref = Process.monitor(pid)

            receive do
              {:DOWN, ^ref, :process, ^pid, _} -> :ok
            after
              5_000 -> raise "dead target did not stop"
            end
          end

          Map.put(state, :target, pid)
        end,
        fn state ->
          Dispatch.dispatch(event, {:pid, target: state.target, delivery_mode: :sync, timeout: 2})
        end,
        fn result, state ->
          expect!(result, {:error, if(mode == :timeout, do: :timeout, else: :process_not_alive)})
          if mode == :timeout, do: expect!(Helpers.wait(state.tag, :called, 1), :ok)
          :ok
        end,
        %{timeout_ms: if(mode == :timeout, do: 2, else: nil)}
      )
    end
  end

  defp consumer(state, index, count, paused?) do
    pid =
      Helpers.worker(state, fn ->
        send(state.owner, {state.tag, :ready, index, :ok})
        if paused?, do: receive(do: (:consume -> :ok))
        consume(state, index, count, [], 0)
      end)

    :ok = Helpers.wait(state.tag, :ready, index)

    {:ok, _} =
      Bus.subscribe(state.bus, "bench.**", target: pid, subscription_id: "consumer#{index}")

    pid
  end

  defp consume(state, index, expected, events, count) do
    receive do
      {:signal, %{id: "benchmark-checkpoint"}} ->
        send(state.owner, {state.tag, :drained, index, Enum.reverse(events)})
        Helpers.hold()

      {:signal, event} ->
        if count + 1 == expected, do: send(state.owner, {state.tag, :consumed, index, :ok})
        consume(state, index, expected, [event | events], count + 1)
    end
  end

  defp await_consumers(state) do
    for index <- 1..length(state.consumers),
        do: expect!(Helpers.wait(state.tag, :consumed, index), :ok)

    :ok
  end

  defp drain_consumers(state, expected) do
    checkpoint =
      Jido.Signal.new!(id: "benchmark-checkpoint", type: "bench.checkpoint", source: "/benchmark")

    {:ok, _} = Bus.publish(state.bus, [checkpoint])
    # The checkpoint comes from the same Bus as all data messages. It proves
    # that each consumer has received every preceding delivery, including extras.
    for index <- 1..length(state.consumers),
        do: expect!(Helpers.wait(state.tag, :drained, index), expected)

    :ok
  end

  defp publish_batches(bus, events, size) do
    events
    |> Enum.chunk_every(size)
    |> Enum.flat_map(fn batch ->
      {:ok, records} = Bus.publish(bus, batch)
      records
    end)
  end
end
