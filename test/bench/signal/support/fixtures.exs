defmodule Jido.Bench.Signal.Receiver do
  @moduledoc false
  use GenServer

  def start_link, do: GenServer.start_link(__MODULE__, [])

  @impl true
  def init(messages), do: {:ok, messages}

  @impl true
  def handle_call({:signal, signal}, _from, messages),
    do: {:reply, :ok, [signal | messages]}

  def handle_call(:drain, _from, messages), do: {:reply, Enum.reverse(messages), []}

  @impl true
  def handle_info({:signal, signal}, messages), do: {:noreply, [signal | messages]}
end

defmodule Jido.Bench.Signal.Fixtures do
  @moduledoc false
  alias Jido.Signal
  alias Jido.Signal.{Bus, Codec, Dispatch, Router}
  alias Jido.Bench.Signal.Receiver

  def workloads(size, payload) when size in 1..32 do
    event = signal(payload)

    signal_cases(event) ++
      serialization_cases(event) ++
      router_cases(size * 16, event) ++
      dispatch_cases(size, event) ++ bus_cases(size, event)
  end

  def workloads(_size, _payload), do: raise(ArgumentError, "size must be in 1..32")

  def signal(payload) do
    Signal.new!(
      id: "benchmark-event",
      type: "bench.event.created",
      source: "/benchmark",
      time: "2026-01-01T00:00:00Z",
      data: payload(payload),
      extensions: %{"tenant" => "benchmark"}
    )
  end

  defp payload(:small), do: %{"value" => 42}
  defp payload(:large_map), do: Map.new(1..1_000, &{"key#{&1}", &1 * 2})
  defp payload(:large_binary), do: :binary.copy(<<42>>, 1_048_576)

  defp signal_cases(event) do
    wire = Codec.to_map(event)
    attrs = Map.drop(wire, ["id", "specversion"])

    [
      simple("signal/new", attrs, fn _ -> Signal.new(attrs) end, fn {:ok, result} ->
        expect!(is_binary(result.id) and byte_size(result.id) > 0, true)
        expect!(%{result | id: event.id}, event)
      end),
      simple("signal/new_fixed", wire, fn _ -> Signal.new(wire) end, &expect!(&1, {:ok, event})),
      simple("signal/to_map", event, fn _ -> Codec.to_map(event) end, &expect!(&1, wire)),
      simple(
        "signal/from_map",
        wire,
        fn _ -> Codec.from_map(wire) end,
        &expect!(&1, {:ok, event})
      )
    ]
  end

  defp serialization_cases(event) do
    for format <- [:json, :erlang_term],
        {:ok, encoded} = Codec.serialize(event, format: format),
        workload <- [
          simple(
            "serialization/#{format}/encode",
            event,
            fn _ -> Codec.serialize(event, format: format) end,
            fn {:ok, result} ->
              expect!(Codec.deserialize(result, format: format), {:ok, event})
            end
          ),
          simple(
            "serialization/#{format}/decode",
            encoded,
            fn _ -> Codec.deserialize(encoded, format: format) end,
            &expect!(&1, {:ok, event})
          )
        ],
        do: workload
  end

  defp router_cases(count, event) do
    exact_specs = for index <- 1..count, do: {"bench.item#{index}.created", index}
    exact = Router.new!(exact_specs)
    matching = %{event | type: "bench.item#{count}.created"}
    missing = %{event | type: "missing.event"}

    # Equal paths check priority and registration order. Wildcards also check
    # class and specificity, with unrelated exact paths filling the index.
    mixed_specs =
      exact_specs ++
        [
          {matching.type, :priority, 50},
          {"bench.*.created", :single_first, -100},
          {"bench.*.created", :single_second, -100},
          {"*.item#{count}.created", :less_specific, 100},
          {"bench.**", :multi, 100}
        ]

    mixed = Router.new!(mixed_specs)

    conditional =
      Router.new!(
        for index <- 1..count do
          {matching.type, fn signal -> signal.source == "/benchmark" and rem(index, 2) == 0 end, index, 0}
        end
      )

    expected = [:priority, count, :single_first, :single_second, :less_specific, :multi]

    [
      simple("router/build", mixed_specs, fn _ -> Router.new(mixed_specs) end, fn {:ok, router} ->
        expect!(Router.count(router), count + 5)
        expect!(Router.route(router, matching), {:ok, expected})
      end),
      simple(
        "router/exact",
        exact,
        fn _ -> Router.route(exact, matching) end,
        &expect!(&1, {:ok, [count]})
      ),
      simple(
        "router/wildcard",
        mixed,
        fn _ -> Router.route(mixed, matching) end,
        &expect!(&1, {:ok, expected})
      ),
      simple("router/miss", mixed, fn _ -> Router.route(mixed, missing) end, fn
        {:error, %Jido.Error.RoutingError{}} -> :ok
      end),
      simple(
        "router/predicate",
        conditional,
        fn _ -> Router.route(conditional, matching) end,
        &expect!(&1, {:ok, Enum.filter(1..count, fn index -> rem(index, 2) == 0 end)})
      )
    ]
  end

  defp dispatch_cases(size, event) do
    noop =
      simple(
        "dispatch/noop",
        event,
        fn _ -> Dispatch.dispatch(event, {:noop, []}) end,
        &expect!(&1, :ok)
      )

    deliveries =
      for {name, mode, count} <- [
            {"pid_async", :async, 1},
            {"pid_sync", :sync, 1},
            {"fanout", :async, size}
          ] do
        %{
          name: "dispatch/#{name}",
          retained: event,
          setup: fn _ ->
            receivers = for _ <- 1..count, do: start_receiver!()
            targets = for pid <- receivers, do: {:pid, [target: pid, delivery_mode: mode]}
            %{receivers: receivers, targets: targets}
          end,
          run: fn state -> Dispatch.dispatch(event, state.targets) end,
          check: fn result, state ->
            expect!(result, :ok)
            # Dispatch and drain have the same sender. The drain call confirms
            # receipt of every preceding async message at each receiver.
            for pid <- state.receivers, do: expect!(GenServer.call(pid, :drain), [event])
            :ok
          end,
          cleanup: fn state -> Enum.each(state.receivers, &stop!/1) end
        }
      end

    [noop | deliveries]
  end

  defp bus_cases(size, event) do
    events =
      for index <- 1..size, do: %{event | id: "event#{index}", type: "bench.item#{index}.created"}

    for mode <- [
          :publish,
          :fanout,
          :replay,
          :replay_filtered,
          :durable_ack,
          :retention,
          :subscribe_churn
        ] do
      %{
        name: "bus/#{mode}",
        retained: events,
        setup: fn _ -> setup_bus(mode, size, events) end,
        run: fn state -> run_bus(mode, state, size, events) end,
        check: fn result, state -> check_bus(mode, result, state, size, events) end,
        cleanup: fn state -> stop!(state.bus) end
      }
    end
  end

  defp setup_bus(mode, size, events) do
    name = "signal-bench-#{System.unique_integer([:positive, :monotonic])}"
    {:ok, bus} = Bus.start_link(name: name, max_log_size: size)

    try do
      case mode do
        :fanout ->
          for index <- 1..size do
            {:ok, _} = Bus.subscribe(bus, "bench.**", subscription_id: "subscriber#{index}")
          end

        :durable_ack ->
          {:ok, "durable"} = Bus.subscribe(bus, "bench.**", durable: "durable")
          {:ok, _} = Bus.publish(bus, events)

        mode when mode in [:replay, :replay_filtered, :retention] ->
          {:ok, _} = Bus.publish(bus, events)

        _ ->
          :ok
      end

      %{bus: bus}
    catch
      kind, reason ->
        stop!(bus)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp run_bus(:publish, state, _size, events), do: Bus.publish(state.bus, events)
  defp run_bus(:fanout, state, _size, events), do: Bus.publish(state.bus, [hd(events)])
  defp run_bus(:retention, state, _size, events), do: Bus.publish(state.bus, events)
  defp run_bus(:replay, state, _size, _events), do: Bus.replay(state.bus, "bench.**")

  defp run_bus(:replay_filtered, state, size, _events),
    do: Bus.replay(state.bus, "bench.item#{size}.*", after: 0, limit: 1)

  defp run_bus(:durable_ack, state, size, _events) do
    for _ <- 1..size do
      receive do
        {:signal, "durable", record} ->
          :ok = Bus.ack(state.bus, "durable", record.cursor)
          record
      after
        5_000 -> raise "durable delivery missing"
      end
    end
  end

  defp run_bus(:subscribe_churn, state, size, _events) do
    for index <- 1..size do
      {:ok, id} = Bus.subscribe(state.bus, "bench.**", subscription_id: "churn#{index}")
      :ok = Bus.unsubscribe(state.bus, id)
    end
  end

  defp check_bus(:durable_ack, records, _state, _size, events) do
    check_records(records, events, 1)
    empty_mailbox!()
  end

  defp check_bus(:subscribe_churn, results, state, size, events) do
    expect!(results, List.duplicate(:ok, size))
    {:ok, _} = Bus.publish(state.bus, events)
    empty_mailbox!()
  end

  defp check_bus(mode, {:ok, records}, state, size, events) do
    case mode do
      :fanout ->
        event = hd(events)
        check_records(records, [event], 1)

        for _ <- 1..size do
          receive do
            {:signal, received} -> expect!(received, event)
          after
            0 -> raise "fanout delivery missing"
          end
        end

      :retention ->
        check_records(records, events, size + 1)
        {:ok, retained} = Bus.replay(state.bus)
        check_records(retained, events, size + 1)

      :replay_filtered ->
        check_records(records, [List.last(events)], size)

      _ ->
        check_records(records, events, 1)
    end

    # The synchronous Bus reply follows all sends from this Bus. It is the
    # barrier for both delivery and absence checks in the caller mailbox.
    empty_mailbox!()
  end

  defp check_records(records, events, first_cursor) do
    expect!(Enum.map(records, & &1.signal), events)

    expect!(
      Enum.map(records, & &1.cursor),
      Enum.to_list(first_cursor..(first_cursor + length(events) - 1))
    )

    expect!(Enum.all?(records, &(is_binary(&1.id) and byte_size(&1.id) > 0)), true)
  end

  defp empty_mailbox! do
    receive do
      {:signal, _event} -> raise "unexpected Signal delivery"
      {:signal, _id, _record} -> raise "unexpected durable delivery"
    after
      0 -> :ok
    end
  end

  defp simple(name, retained, run, check) do
    %{
      name: name,
      retained: retained,
      setup: fn _ -> nil end,
      run: run,
      check: fn result, _ -> check.(result) end
    }
  end

  defp start_receiver! do
    {:ok, pid} = Receiver.start_link()
    pid
  end

  defp stop!(pid) do
    ref = Process.monitor(pid)
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5_000)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      5_000 -> raise "benchmark process did not stop"
    end
  end

  defp expect!(actual, expected) do
    if actual != expected, do: raise("benchmark returned an incorrect result")
    :ok
  end
end
