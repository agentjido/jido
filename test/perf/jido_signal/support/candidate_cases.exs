defmodule Jido.Test.Perf.Signal.CandidateCases do
  @moduledoc false
  alias Jido.Signal
  alias Jido.Signal.{Bus, Codec}
  alias Jido.Signal.Bus.Store.Memory
  alias Jido.Test.Perf.Signal.Helpers
  import Helpers, only: [plain: 5, stateful: 6, expect!: 2]

  def workloads(size) when size in 2..32 do
    (text_cases(size) ++
       term_cases(size) ++
       publish_cases(size) ++
       replay_cases(size) ++
       removal_cases(size) ++ retention_cases(size))
    |> Enum.map(&Map.put(&1, :id, "#{&1.name}/candidates/#{size}"))
  end

  defp text_cases(size) do
    for {kind, unit} <- [ascii: "abcdefg ", mixed: "abcdeé ", unicode: "日本語", emoji: "😀"],
        operation <- [:to_map, :from_map, :json] do
      data = :binary.copy(unit, div(size * 32_768, byte_size(unit)))
      text_case(kind, data, operation)
    end ++
      for operation <- [:to_map, :from_map, :json] do
        text_case(:invalid_tail, :binary.copy("a", size * 32_768) <> <<255>>, operation)
      end
  end

  defp text_case(kind, data, operation) do
    signal = event(data)
    wire = Codec.to_map(signal)
    # Use data directly to exercise validation on input, including invalid UTF-8.
    input = wire |> Map.delete("data_base64") |> Map.put("data", data)
    {:ok, expected_input} = Codec.from_map(input)
    {:ok, json} = Codec.serialize(signal)

    {run, expected} =
      case operation do
        :to_map -> {fn _ -> Codec.to_map(signal) end, wire}
        :from_map -> {fn _ -> Codec.from_map(input) end, {:ok, expected_input}}
        :json -> {fn _ -> Codec.serialize(signal) end, {:ok, json}}
      end

    plain("candidate/utf8/#{kind}/#{operation}", signal, run, &expect!(&1, expected), %{
      bytes: byte_size(data),
      text: kind
    })
  end

  defp term_cases(size) do
    for {kind, data} <- [
          binary: :binary.copy("a", size * 32_768),
          nested: %{"items" => for(n <- 1..(size * 128), do: %{"n" => n, "v" => "value"})},
          raw: %{blob: :binary.copy(<<255>>, size * 32_768), pair: {:ok, 42}}
        ] do
      signal = event(data)
      {:ok, encoded} = Codec.serialize(signal, format: :erlang_term)

      plain(
        "candidate/term/#{kind}",
        encoded,
        fn _ -> Codec.deserialize(encoded, format: :erlang_term) end,
        &expect!(&1, {:ok, signal}),
        %{bytes: byte_size(encoded)}
      )
    end
  end

  defp publish_cases(size) do
    events = Helpers.events(size * 8)

    for kind <- [:empty, :miss, :match] do
      stateful(
        "candidate/publish/#{kind}",
        events,
        fn state ->
          bus = Helpers.bus(state, length(events) * 8)

          if kind != :empty do
            path = if kind == :match, do: "bench.**", else: "absent.**"
            {:ok, _} = Bus.subscribe(bus, path)
          end

          Map.put(state, :bus, bus)
        end,
        fn state -> for _ <- 1..8, do: Bus.publish(state.bus, events) end,
        fn results, state ->
          for {{:ok, records}, round} <- Enum.with_index(results) do
            Helpers.records(records, events, round * length(events) + 1)
          end

          {:ok, replay} = Bus.replay(state.bus)
          expect!(length(replay), length(events) * 8)

          if kind == :match do
            for _ <- 1..8, event <- events do
              receive do
                {:signal, ^event} -> :ok
              after
                0 -> raise "publication delivery missing"
              end
            end
          end

          Helpers.empty_mailbox!()
        end,
        %{
          records: length(events) * 8,
          batches: 8,
          subscribers: if(kind == :empty, do: 0, else: 1)
        }
      )
    end
  end

  defp replay_cases(size) do
    count = size * 256
    records = for n <- 1..count, do: record(n)
    {:ok, state} = Memory.init(max_records: count)
    {:ok, state} = Memory.append(records, state)

    for {kind, opts, expected} <- [
          {:exact, [path: "bench.item#{count}.created"], [List.last(records)]},
          {:single, [path: "bench.*.created"], records},
          {:multi, [path: "**.item#{count}.**", limit: 1], [List.last(records)]},
          {:miss, [path: "absent.**"], []},
          {:cursor, [path: "bench.**", after_cursor: count - 2, limit: 1], [Enum.at(records, -2)]}
        ] do
      plain(
        "candidate/replay/#{kind}",
        state,
        fn _ -> Memory.read(opts, state) end,
        &expect!(&1, {:ok, expected}),
        %{records: count, returned: length(expected)}
      )
    end
  end

  defp removal_cases(size) do
    count = size * 16
    removed = div(count, 2)

    for kind <- [:ephemeral, :durable], shape <- [:exact, :shared, :single, :multi] do
      stateful(
        "candidate/remove/#{kind}/#{shape}",
        {count, shape},
        fn state ->
          bus = Helpers.bus(state, 1)

          for n <- 1..count do
            opts =
              if kind == :durable, do: [durable: "sub#{n}"], else: [subscription_id: "sub#{n}"]

            {:ok, _} = Bus.subscribe(bus, subscription_path(shape, n), opts)
          end

          Map.put(state, :bus, bus)
        end,
        fn state -> Bus.delete_subscription(state.bus, "sub#{removed}") end,
        fn result, state ->
          expect!(result, :ok)

          expect!(
            Bus.delete_subscription(state.bus, "sub#{removed}"),
            {:error, :subscription_not_found}
          )

          actual = :sys.get_state(state.bus)
          expect!(map_size(actual.subscriptions), count - 1)
          expected = for n <- 1..count, n != removed, do: "sub#{n}"
          {:ok, routes} = Jido.Signal.Router.list(actual.router)
          expect!(Enum.map(routes, & &1.target), expected)
          expect!(Jido.Signal.Router.count(actual.router), count - 1)
        end,
        %{subscriptions: count, removed: removed, kind: kind, shape: shape}
      )
    end
  end

  defp subscription_path(:exact, n), do: "bench.item#{n}.created"
  defp subscription_path(:shared, _), do: "bench.**"
  defp subscription_path(:single, n), do: "bench.item#{n}.*"
  defp subscription_path(:multi, n), do: "bench.**.item#{n}.**"

  defp retention_cases(size) do
    capacity = size * 128
    batch = size * 4
    initial = for n <- 1..capacity, do: record(n)
    incoming = for n <- (capacity + 1)..(capacity + batch), do: record(n)

    for {kind, subscriptions, pattern} <- [
          {:empty, 0, "absent.**"},
          {:one, 1, "absent.**"},
          {:many, 32, "absent.**"},
          {:pinned, 1, "bench.item1.**"},
          {:blocked, 1, "bench.**"}
        ] do
      {:ok, state} = Memory.init(max_records: capacity)
      {:ok, state} = Memory.append(initial, state)

      state =
        Enum.reduce(indices(subscriptions), state, fn n, state ->
          {:ok, state} = Memory.put_subscription(definition("sub#{n}", pattern), state)
          state
        end)

      expected =
        if kind == :pinned,
          do: [hd(initial)] ++ Enum.drop(initial, batch + 1) ++ incoming,
          else: Enum.drop(initial, batch) ++ incoming

      plain(
        "candidate/retention/#{kind}",
        {state, incoming},
        fn _ -> Memory.append(incoming, state) end,
        fn result ->
          if kind == :blocked do
            expect!(result, {:error, {:store_full, ["sub1"]}})
            expect!(Memory.read([], state), {:ok, initial})
          else
            {:ok, retained} = result
            {:ok, records} = Memory.read([], retained)
            expect!(records, expected)
            expect!(length(records), capacity)
          end
        end,
        %{records: capacity, batch: batch, durable_subscriptions: subscriptions}
      )
    end
  end

  defp indices(0), do: []
  defp indices(count), do: 1..count

  defp event(data),
    do: Signal.new!(id: "candidate", type: "bench.created", source: "/bench", data: data)

  defp record(cursor) do
    %{
      "format_version" => 1,
      "id" => "record#{cursor}",
      "cursor" => cursor,
      "type" => "bench.item#{cursor}.created",
      "created_at" => "2026-09-05T00:00:00Z",
      "signal" => %{"id" => "record#{cursor}"}
    }
  end

  defp definition(id, path) do
    %{
      "format_version" => 1,
      "id" => id,
      "path" => path,
      "cursor" => 0,
      "created_at" => "2026-09-05T00:00:00Z"
    }
  end
end
