defmodule Jido.Signal.PublicBoundaryErrorsTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Context
  alias Jido.Signal.Router
  alias Jido.Signal.Router.Route
  alias Jido.Signal.Trace

  describe "Signal error boundaries" do
    test "returns validation errors for struct attribute maps" do
      for attrs <- [%URI{}, MapSet.new([:item])] do
        for result <- [
              Signal.new(attrs),
              Signal.new("event", %{}, attrs),
              Signal.from_map(attrs),
              Signal.new(type: "event", source: "/test", extensions: attrs),
              Context.normalize(attrs),
              JidoSignalTest.Fixtures.Signals.UserCreated.new(%{}, attrs),
              Signal.deserialize(:erlang.term_to_binary(attrs), format: :erlang_term)
            ] do
          assert {:error, _reason} = result
        end
      end

      data = %URI{path: "/domain"}
      assert {:ok, signal} = Signal.new("event", data, source: "/test", tenantid: "one")
      assert signal.data == data
      assert signal.extensions == %{"tenantid" => "one"}
    end

    test "reject invalid constructor and definition inputs" do
      invalid = Process.get({__MODULE__, :invalid_definition}, :invalid)

      assert {:error, "expected Signal options to be a map or keyword list"} =
               Signal.__normalize_definition_attrs__(invalid, %{})

      assert {:error, "parse error: expected a map or keyword list"} = Signal.new(invalid)

      assert {:error, message} = Signal.new(:invalid, %{}, [])
      assert message =~ "expected new/3"

      assert_raise RuntimeError, ~r/expected a map or keyword list/, fn ->
        Signal.new!(invalid)
      end

      assert_raise ArgumentError, ~r/invalid signal: expected new\/3/, fn ->
        Signal.new!(invalid, %{}, [])
      end
    end

    test "raises at the serialization convenience boundary" do
      assert_raise RuntimeError, ~r/serialization failed/, fn ->
        Signal.serialize!(:invalid)
      end
    end
  end

  describe "Context error boundaries" do
    test "returns stable fallback values for invalid Signal inputs" do
      assert {:error, "expected a Signal struct"} = Context.put(:invalid, "tenantid", "one")
      assert Context.get(:invalid, "tenantid") == nil
      assert Context.delete(:invalid, "tenantid") == :invalid
      assert Context.names(:invalid) == []
    end

    test "rejects invalid extension names and values" do
      assert {:error, "invalid extension name 42"} = Context.normalize_name(42)

      assert {:error, message} = Context.normalize(%{"tenantid" => 2_147_483_648})
      assert message =~ "extension values"
    end
  end

  describe "Router error boundaries" do
    test "rejects improper route and path collections before traversal" do
      router = Router.new!({"valid.path", :target})
      route = %Route{path: "valid.path", target: :target}
      invalid = [{"valid.path", :target} | :tail]

      for result <- [
            Router.normalize(invalid),
            Router.new(invalid),
            Router.add(router, invalid),
            Router.merge(router, invalid),
            Router.validate([route | :tail]),
            Router.remove(router, ["valid.path" | :tail])
          ] do
        assert {:error, _} = result
      end

      signal = Signal.new!("valid.path", %{}, source: "/test")
      assert Router.filter([signal | :tail], "**") == []
      assert {:ok, [:target]} = Router.route(router, signal)
    end

    test "rejects invalid route definitions through each public constructor" do
      assert {:error, _error} = Router.normalize(:invalid)
      assert_raise Jido.Signal.Error.InvalidInputError, fn -> Router.new!(:invalid) end

      assert {:ok, router} = Router.new()
      assert {:error, {:invalid_routes, :invalid}} = Router.merge(router, :invalid)
      assert {:error, _error} = Router.validate(:invalid)
      assert {:error, _error} = Router.validate([:invalid])
    end

    test "returns stable routing errors for invalid Signal types" do
      assert {:ok, router} = Router.new()

      nil_type = %Signal{id: "one", source: "/test", type: nil}
      assert {:error, error} = Router.route(router, nil_type)
      assert error.details.reason == :nil_signal_type

      invalid_type = %Signal{id: "two", source: "/test", type: :invalid}
      assert {:error, error} = Router.route(router, invalid_type)
      assert error.details.reason == :invalid_signal_type
    end

    test "uses safe fallbacks for invalid patterns and values" do
      assert Router.filter([], "invalid..path") == []
      assert Router.filter(:invalid, "valid.path") == []
      refute Router.matches?(:invalid, "valid.path")
      refute Router.has_route?(:invalid, "valid.path")
    end

    test "returns a validation error for an invalid Route struct" do
      assert {:error, _error} = Router.normalize(%Route{path: "invalid..path", target: :target})
    end
  end

  describe "Trace error boundaries" do
    test "exposes its schema and rejects invalid values" do
      assert %Zoi.Types.Struct{} = Trace.schema()
      refute Trace.valid?(:invalid)
      assert Trace.get(:invalid) == nil
      assert {:error, :invalid_traceparent} = Trace.from_traceparent(:invalid)
      assert {:error, "expected a Signal and Trace"} = Trace.put(:invalid, :invalid)
    end

    test "raises when formatting or deriving from an invalid Trace" do
      invalid = %Trace{
        trace_id: String.duplicate("0", 32),
        span_id: String.duplicate("0", 16),
        trace_flags: "00"
      }

      assert_raise ArgumentError, "invalid parent Trace", fn -> Trace.child(invalid) end
      assert_raise ArgumentError, "invalid Trace", fn -> Trace.to_traceparent(invalid) end
    end
  end
end
