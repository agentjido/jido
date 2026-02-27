defmodule JidoTest.Observe.SpanCtxTest do
  use ExUnit.Case, async: true

  alias Jido.Observe.SpanCtx

  @valid_attrs %{
    event_prefix: [:jido, :test],
    start_time: 1_000_000,
    start_system_time: 2_000_000,
    metadata: %{key: "value"}
  }

  describe "schema/0" do
    test "returns the Zoi schema" do
      schema = SpanCtx.schema()
      assert is_struct(schema)
    end
  end

  describe "new/1" do
    test "creates a SpanCtx with valid attrs" do
      assert {:ok, %SpanCtx{} = span_ctx} = SpanCtx.new(@valid_attrs)
      assert span_ctx.event_prefix == [:jido, :test]
      assert span_ctx.start_time == 1_000_000
      assert span_ctx.start_system_time == 2_000_000
      assert span_ctx.metadata == %{key: "value"}
    end

    test "creates a SpanCtx with optional tracer_ctx" do
      attrs = Map.put(@valid_attrs, :tracer_ctx, {:opentelemetry, :ctx})
      assert {:ok, %SpanCtx{tracer_ctx: {:opentelemetry, :ctx}}} = SpanCtx.new(attrs)
    end

    test "creates a SpanCtx with optional tracer_module" do
      attrs = Map.put(@valid_attrs, :tracer_module, Jido.Observe.NoopTracer)
      assert {:ok, %SpanCtx{tracer_module: Jido.Observe.NoopTracer}} = SpanCtx.new(attrs)
    end

    test "returns error for non-map input" do
      assert {:error, error} = SpanCtx.new("not a map")
      assert error.message == "SpanCtx requires a map"
    end

    test "returns error for nil input" do
      assert {:error, error} = SpanCtx.new(nil)
      assert error.message == "SpanCtx requires a map"
    end

    test "returns error for list input" do
      assert {:error, error} = SpanCtx.new([])
      assert error.message == "SpanCtx requires a map"
    end

    test "returns error for missing required fields" do
      assert {:error, _reason} = SpanCtx.new(%{})
    end
  end

  describe "new!/1" do
    test "returns SpanCtx on success" do
      span_ctx = SpanCtx.new!(@valid_attrs)
      assert %SpanCtx{} = span_ctx
      assert span_ctx.event_prefix == [:jido, :test]
    end

    test "raises on invalid attrs" do
      assert_raise Jido.Error.ValidationError, fn ->
        SpanCtx.new!(%{})
      end
    end

    test "raises on non-map input" do
      assert_raise Jido.Error.ValidationError, fn ->
        SpanCtx.new!("not a map")
      end
    end
  end
end
