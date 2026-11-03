Code.require_file("../../../property/signal/support/fuzz.exs", __DIR__)

defmodule JidoTest.Property.Signal.DiagnosticsTest do
  use ExUnit.Case, async: true
  import StreamData
  alias Jido.Error
  alias Jido.Signal
  alias Jido.Signal.Boundary
  alias JidoTest.Property.Signal.Fuzz

  @classes [
    {:validation_error, :validation_error, false},
    {:execution_error, :execution_error, false},
    {:routing_error, :routing_error, false},
    {:timeout_error, :timeout, true},
    {:dispatch_error, :routing_error, false},
    {:internal_error, :internal_error, false}
  ]
  @reasons [
    {:timeout, true},
    {:closed, true},
    {:econnrefused, true},
    {:queue_full, true},
    {{:http_status, 429}, true},
    {{:http_status, 503}, true},
    {{:status_error, 425, "body"}, true},
    {{:transport, :timeout}, true},
    {{:http_status, 404}, false},
    {:invalid, false},
    {{:exception, :bad}, false}
  ]

  for {suite, runs, bound} <- [{:property, 40, 8}, {:fuzz, 500, 30}] do
    @tag [
      {suite, true},
      max_runs: runs,
      max_run_time: if(suite == :fuzz, do: 300_000, else: 10_000),
      timeout: if(suite == :fuzz, do: 900_000, else: 90_000)
    ]
    @tag contracts: ["ERROR-001"]
    @tag contract_cases: [
           "ERROR-001/type-retry-table",
           "ERROR-001/grouped-improper",
           "ERROR-001/compound-secret-keys",
           "ERROR-001/summary-bounds",
           "ERROR-001/long-module-names",
           "ERROR-001/no-stacktrace"
         ]
    test "#{suite}: errors and diagnostic values stay bounded", context do
      generator =
        fixed_map(%{
          "depth" => integer(0..unquote(bound)),
          "size" => integer(0..4000),
          "width" => integer(0..80),
          "key" => member_of(~w(tuple map list improper))
        })

      examples =
        for key <- ~w(tuple map list improper),
            do: %{"depth" => 20, "size" => 4000, "width" => 80, "key" => key}

      Fuzz.check("diagnostics", generator, Map.to_list(context) ++ [examples: examples], &check/1)
    end
  end

  defp check(%{"depth" => depth, "size" => size, "width" => width, "key" => kind}) do
    secret = "private-secret-marker"
    text = String.duplicate("é", size)

    key =
      case kind do
        "tuple" -> {:compound, %{token: secret}}
        "map" -> %{authorization: secret}
        "list" -> [%{password: secret}]
        "improper" -> [%{api_key: secret} | %{secret: secret}]
      end

    uri = URI.parse("https://user:#{secret}@example.test/#{text}?token=#{secret}##{secret}")
    signal = Signal.new!("event.a", %{"password" => secret, "nested" => text}, source: "/p")
    signal = %{signal | id: text, type: text, subject: text, source: text}

    nested =
      Enum.reduce(List.duplicate(nil, depth), signal, fn _, inner -> %{signal | data: inner} end)

    wide = Map.new(for i <- Enum.take(Stream.iterate(0, &(&1 + 1)), width), do: {"key#{i}", text})

    values =
      [
        %{key => "public", "password" => secret, "wide" => wide},
        uri,
        nested,
        make_ref(),
        self(),
        fn -> text end,
        <<255, 0, 254>>,
        Date.new!(2026, 9, 29),
        ~T[12:00:00],
        ~N[2026-09-29 12:00:00],
        ~U[2026-09-29 12:00:00Z]
      ] ++ JidoSignalTest.Fixtures.Diagnostics.values()

    for {profile, max_binary, max_items, max_depth} <- [
          {:telemetry, 160, 10, 3},
          {:transport, 1024, 50, 6}
        ],
        value <- values do
      safe = Boundary.sanitize(value, profile)
      refute inspect(safe, limit: :infinity, printable_limit: :infinity) =~ secret
      bounded(safe, max_binary + 3, max_items + 1, max_depth + 2, 0)
      preview = Boundary.preview(value, profile, max_length: 32)
      assert byte_size(preview) <= 35
      refute preview =~ secret
    end

    for {function, type, retry?} <- @classes do
      error =
        error(function, "diagnostic", %{
          payload: %{key => "public", password: secret},
          text: text
        })

      assert Error.type(error) == type
      assert Error.retryable?(error) == retry?
      map = Error.to_map(error)
      assert map.type == type and map.retryable? == retry?
      refute Map.has_key?(map, :stacktrace)
      refute inspect(map, limit: :infinity, printable_limit: :infinity) =~ secret
      bounded(map.details, 1027, 51, 8, 0)
    end

    for {reason, retry?} <- @reasons,
        function <- [:execution_error, :dispatch_error, :internal_error] do
      assert Error.retryable?(error(function, "reason", %{reason: reason})) == retry?
    end

    timeout = Error.timeout_error("timeout")
    refute Error.retryable?(%{errors: [timeout | :tail]})
    assert Error.retryable?(%{errors: [timeout]})

    refute Error.retryable?(error(:dispatch_error, "wrapped", %{reason: %{errors: [timeout | :tail]}}))

    assert is_map(Error.to_map(RuntimeError.exception("foreign")))
    ["key-#{kind}", "depth-#{depth}", "wide-#{width > 50}"]
  end

  defp bounded(value, max_binary, _, _, _) when is_binary(value),
    do: assert(byte_size(value) <= max_binary)

  defp bounded(value, max_binary, max_items, max_depth, depth) when is_map(value) do
    assert depth <= max_depth
    assert map_size(value) <= max_items

    Enum.each(value, fn {key, item} ->
      bounded(key, max_binary, max_items, max_depth, depth + 1)
      bounded(item, max_binary, max_items, max_depth, depth + 1)
    end)
  end

  defp bounded(value, max_binary, max_items, max_depth, depth) when is_list(value) do
    assert depth <= max_depth
    assert length(value) <= max_items
    Enum.each(value, &bounded(&1, max_binary, max_items, max_depth, depth + 1))
  end

  defp bounded(_value, _, _, _, _), do: :ok

  defp error(:dispatch_error, message, details),
    do: Error.routing_error(message, Map.put(details, :operation, :dispatch))

  defp error(function, message, details), do: apply(Error, function, [message, details])
end
