defmodule Jido.Signal.TraceTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Trace

  @traceparent "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

  describe "new/1 and child/1" do
    test "creates valid root and child Trace values" do
      root = Trace.new(tracestate: "vendor=value")
      child = Trace.child(root)

      assert %Trace{} = root
      assert Trace.valid?(root)
      assert byte_size(root.trace_id) == 32
      assert byte_size(root.span_id) == 16
      assert root.trace_flags == "00"

      assert child.trace_id == root.trace_id
      assert child.span_id != root.span_id
      assert child.trace_flags == root.trace_flags
      assert child.tracestate == root.tracestate
    end

    test "uses explicit trace flags without selecting sampling policy" do
      assert Trace.new().trace_flags == "00"
      assert Trace.new(trace_flags: "01").trace_flags == "01"
      assert Trace.new(trace_flags: "09").trace_flags == "09"
    end

    test "rejects invalid or unknown options" do
      assert_raise ArgumentError, fn -> Trace.new(trace_flags: "zz") end
      assert_raise ArgumentError, fn -> Trace.new(causation_id: "old-field") end
    end
  end

  describe "W3C traceparent" do
    test "parses and formats version 00 without losing flags" do
      assert {:ok, trace} = Trace.from_traceparent(@traceparent, "vendor=value")

      assert trace.trace_id == "4bf92f3577b34da6a3ce929d0e0e4736"
      assert trace.span_id == "00f067aa0ba902b7"
      assert trace.trace_flags == "01"
      assert trace.tracestate == "vendor=value"
      assert Trace.to_traceparent(trace) == @traceparent
      assert Trace.valid?(@traceparent)
    end

    test "rejects invalid versions, flags, and IDs" do
      assert {:error, :invalid_traceparent} =
               Trace.from_traceparent("01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")

      assert {:error, :invalid_traceparent} =
               Trace.from_traceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-zz")

      assert {:ok, trace} =
               Trace.from_traceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-09")

      assert trace.trace_flags == "09"

      assert {:error, :invalid_traceparent} =
               Trace.from_traceparent("00-00000000000000000000000000000000-00f067aa0ba902b7-01")

      assert {:error, :invalid_traceparent} =
               Trace.from_traceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01")
    end

    test "discards invalid tracestate without rejecting traceparent" do
      assert {:ok, trace} =
               Trace.from_traceparent(@traceparent, String.duplicate("x", 513))

      assert trace.tracestate == nil
    end

    test "validates W3C tracestate grammar" do
      valid = "vendor=value,1@system=opaque-123"
      assert {:ok, trace} = Trace.from_traceparent(@traceparent, valid)
      assert trace.tracestate == valid

      invalid_values = [
        "Vendor=value",
        "vendor=one,vendor=two",
        "vendor=value\r\ninjected=true",
        "vendor=value,\r\ninjected=true",
        Enum.map_join(1..33, ",", &"vendor#{&1}=value")
      ]

      for tracestate <- invalid_values do
        assert {:ok, trace} = Trace.from_traceparent(@traceparent, tracestate)
        assert trace.tracestate == nil
        assert_raise ArgumentError, fn -> Trace.new(tracestate: tracestate) end
      end
    end

    test "preserves ASCII whitespace and empty tracestate members" do
      values = [
        "a=one, b=two",
        "a=one,  b=two",
        "a=one,\tb=two",
        "a=one, \t b=two",
        " \ta=one\t , b=two \t",
        "a=opaque value ,,, \t,b=two,",
        "vendor=value ",
        "",
        " \t",
        ",,"
      ]

      for value <- values do
        assert {:ok, trace} = Trace.from_traceparent(@traceparent, value)
        assert trace.tracestate == value
        assert Trace.new(tracestate: value).tracestate == value
      end
    end

    test "counts nonempty members and enforces tracestate byte and character limits" do
      members = Enum.map_join(1..32, ",", &"vendor#{&1}=value")
      assert {:ok, trace} = Trace.from_traceparent(@traceparent, ",," <> members <> ",,")
      assert trace.tracestate == ",," <> members <> ",,"

      at_limit = "a=" <> String.duplicate("x", 256) <> ",b=" <> String.duplicate("y", 251)
      assert byte_size(at_limit) == 512
      assert {:ok, trace} = Trace.from_traceparent(@traceparent, at_limit)
      assert trace.tracestate == at_limit

      for value <- [
            at_limit <> " ",
            "a=" <> String.duplicate("x", 257),
            "a=one, \ta=two",
            "a=one,\rb=two",
            "a=one,\nb=two",
            "a=one,\vb=two",
            "a=one,\u00A0b=two",
            "a=one\tb=two",
            "a=one=b=two"
          ] do
        assert {:ok, trace} = Trace.from_traceparent(@traceparent, value)
        assert trace.tracestate == nil
        assert_raise ArgumentError, fn -> Trace.new(tracestate: value) end
      end
    end
  end

  describe "Signal carrier" do
    test "puts, gets, and deletes flat W3C context attributes" do
      signal = Signal.new!(type: "test.created", source: "/test")
      trace = Trace.new(trace_flags: "01", tracestate: "vendor=value")

      assert {:ok, traced} = Trace.put(signal, trace)
      assert traced.extensions["traceparent"] == Trace.to_traceparent(trace)
      assert traced.extensions["tracestate"] == "vendor=value"
      assert Trace.get(traced) == trace

      clean = Trace.delete(traced)
      assert Trace.get(clean) == nil
      refute Map.has_key?(clean.extensions, "traceparent")
      refute Map.has_key?(clean.extensions, "tracestate")
    end

    test "replaces stale tracestate" do
      signal = Signal.new!(type: "test.created", source: "/test")
      assert {:ok, signal} = Trace.put(signal, Trace.new(tracestate: "vendor=old"))
      assert {:ok, signal} = Trace.put(signal, Trace.new())

      refute Map.has_key?(signal.extensions, "tracestate")
    end

    test "returns nil for missing or invalid trace context" do
      signal = Signal.new!(type: "test.created", source: "/test")
      assert Trace.get(signal) == nil

      invalid = %{signal | extensions: %{"traceparent" => "invalid"}}
      assert Trace.get(invalid) == nil
    end

    test "ensures a root Trace and preserves an existing Trace" do
      signal = Signal.new!(type: "test.created", source: "/test")

      assert {:ok, traced, trace} = Trace.ensure(signal, trace_flags: "01")
      assert Trace.get(traced) == trace

      assert {:ok, same_signal, same_trace} = Trace.ensure(traced)
      assert same_signal == traced
      assert same_trace == trace
    end

    test "rejects an invalid Trace struct" do
      signal = Signal.new!(type: "test.created", source: "/test")

      invalid = %Trace{
        trace_id: String.duplicate("0", 32),
        span_id: "00f067aa0ba902b7",
        trace_flags: "00"
      }

      assert {:error, error} = Trace.put(signal, invalid)
      assert error =~ "invalid Trace"
    end

    test "survives Signal JSON serialization" do
      signal = Signal.new!(type: "test.created", source: "/test")
      trace = Trace.new(trace_flags: "01", tracestate: "vendor=value")
      assert {:ok, traced} = Trace.put(signal, trace)

      assert {:ok, json} = Signal.serialize(traced)
      assert {:ok, restored} = Signal.deserialize(json)
      assert Trace.get(restored) == trace
    end
  end
end
