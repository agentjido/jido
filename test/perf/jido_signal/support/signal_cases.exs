defmodule Jido.Test.Perf.Signal.TypedSignal do
  @moduledoc false
  use Jido.Signal,
    type: "bench.typed",
    default_source: "/benchmark",
    schema:
      Zoi.object(%{
        items: Zoi.list(Zoi.integer()),
        meta: Zoi.object(%{name: Zoi.string(), count: Zoi.integer()})
      })
end

defmodule Jido.Test.Perf.Signal.SignalCases do
  @moduledoc false
  alias Jido.Trace
  alias Jido.Signal
  alias Jido.Signal.{Codec, Context}
  alias Jido.Test.Perf.Signal.{Helpers, TypedSignal}
  import Helpers, only: [plain: 4, plain: 5, expect!: 2]

  def workloads(size) do
    [event] = Helpers.events(1)
    data = %{items: Enum.to_list(1..size), meta: %{name: "benchmark", count: size}}
    traceparent = "00-11111111111111111111111111111111-2222222222222222-01"
    {:ok, trace} = Trace.from_traceparent(traceparent, "bench=1")
    {:ok, traced} = Context.put_trace(event, trace)
    {:ok, context} = Signal.put_context(event, "tenant", "benchmark")

    core = [
      plain(
        "signal/typed",
        data,
        fn _ -> TypedSignal.new(data, id: event.id) end,
        fn {:ok, result} ->
          expect!(result.data, data)

          expect!(
            {result.id, result.type, result.source},
            {event.id, "bench.typed", "/benchmark"}
          )
        end,
        %{items: size}
      ),
      plain(
        "signal/typed_invalid",
        data,
        fn _ -> TypedSignal.new(%{data | items: ["wrong"]}) end,
        fn
          {:error, [%Zoi.Error{} | _]} -> :ok
        end
      ),
      plain(
        "signal/invalid",
        event,
        fn _ -> Signal.new(type: event.type, source: 123) end,
        fn {:error, reason} ->
          expect!(is_binary(reason) and String.contains?(reason, "source"), true)
        end
      ),
      plain("trace/put", event, fn _ -> Context.put_trace(event, trace) end, &expect!(&1, {:ok, traced})),
      plain("trace/get", traced, fn _ -> Context.get_trace(traced) end, &expect!(&1, trace)),
      plain(
        "trace/parse",
        traceparent,
        fn _ -> Trace.from_traceparent(traceparent, "bench=1") end,
        &expect!(&1, {:ok, trace})
      ),
      plain(
        "trace/format",
        trace,
        fn _ -> Trace.to_traceparent(trace) end,
        &expect!(&1, traceparent)
      ),
      plain("trace/child", trace, fn _ -> Trace.child(trace) end, fn child ->
        expect!(Trace.valid?(child), true)
        expect!(child.trace_id, trace.trace_id)
        expect!(child.trace_flags, trace.trace_flags)
        expect!(child.tracestate, trace.tracestate)
        expect!(child.parent_span_id, trace.span_id)
        expect!(child.causation_id, nil)
        expect!(child.span_id != trace.span_id, true)
      end),
      plain(
        "context/put",
        event,
        fn _ -> Signal.put_context(event, "tenant", "benchmark") end,
        &expect!(&1, {:ok, context})
      )
    ]

    raw =
      Signal.new!(
        type: "bench.raw",
        source: "/benchmark",
        data: :binary.copy(<<255, 0>>, size * 16_384)
      )

    nested_data =
      Enum.reduce(1..min(size, 16), %{"items" => Enum.to_list(1..size)}, fn index, inner ->
        %{"level#{index}" => inner}
      end)

    nested = Signal.new!(type: "bench.nested", source: "/benchmark", data: nested_data)
    batch = Helpers.events(size)

    core ++
      codec_cases("serialization/base64", raw, :json, %{payload_bytes: byte_size(raw.data)}) ++
      codec_cases("serialization/nested", nested, :json, %{depth: min(size, 16)}) ++
      codec_cases("serialization/batch/json", batch, :json, %{records: size}) ++
      codec_cases("serialization/batch/erlang_term", batch, :erlang_term, %{records: size}) ++
      error_cases(event)
  end

  defp codec_cases(name, input, format, dimensions) do
    {:ok, encoded} = Codec.serialize(input, format: format)

    [
      plain(
        "#{name}/encode",
        input,
        fn _ -> Codec.serialize(input, format: format) end,
        fn {:ok, binary} ->
          expect!(Codec.deserialize(binary, format: format), {:ok, input})
        end,
        dimensions
      ),
      plain(
        "#{name}/decode",
        encoded,
        fn _ -> Codec.deserialize(encoded, format: format) end,
        &expect!(&1, {:ok, input}),
        dimensions
      )
    ]
  end

  defp error_cases(event) do
    invalid_wire = event |> Codec.to_map() |> Map.delete("data") |> Map.put("data_base64", "!")
    {:ok, encoded} = Codec.serialize(event)

    [
      plain("serialization/invalid_json", "{", fn _ -> Codec.deserialize("{") end, fn
        {:error, {:json_decode_failed, reason}} when is_binary(reason) -> :ok
      end),
      plain(
        "serialization/invalid_term",
        <<131, 255>>,
        fn _ -> Codec.deserialize(<<131, 255>>, format: :erlang_term) end,
        fn
          {:error, {:erlang_term_decode_failed, reason}} when is_binary(reason) -> :ok
        end
      ),
      plain(
        "serialization/invalid_base64",
        invalid_wire,
        fn _ -> Codec.from_map(invalid_wire) end,
        fn {:error, reason} ->
          expect!(String.contains?(reason, "Base64"), true)
        end
      ),
      plain(
        "serialization/oversized",
        event,
        fn _ -> Codec.serialize(event, max_payload_bytes: 1) end,
        &expect!(&1, {:error, {:payload_too_large, byte_size(encoded), 1}})
      ),
      plain(
        "serialization/oversized_decode",
        encoded,
        fn _ -> Codec.deserialize(encoded, max_payload_bytes: 1) end,
        &expect!(&1, {:error, {:payload_too_large, byte_size(encoded), 1}})
      )
    ]
  end
end
