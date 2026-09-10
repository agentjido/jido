defmodule Jido.Telemetry.OpenTelemetry do
  @moduledoc false

  alias Jido.Signal.Trace, as: SignalTrace

  @ignored_measurements [:duration, :monotonic_time, :system_time]

  defmodule Span do
    @moduledoc false

    @enforce_keys [:span_ctx, :restore_context, :started_by, :terminal_guard]
    defstruct [:span_ctx, :restore_context, :started_by, :terminal_guard]

    @type t :: %__MODULE__{
            span_ctx: term(),
            restore_context: term(),
            started_by: pid(),
            terminal_guard: :atomics.atomics_ref()
          }
  end

  @doc false
  @spec enabled?() :: boolean()
  def enabled? do
    available?() and configured?() and not noop_tracer?(tracer())
  catch
    _, _ -> false
  end

  @doc false
  @spec trace_context(Span.t() | nil) :: map() | nil
  def trace_context(nil), do: nil

  def trace_context(%Span{span_ctx: span_ctx}) do
    if enabled?() and call(:otel_span, :is_valid, [span_ctx]) do
      context = call(:otel_tracer, :set_current_span, [call(:otel_ctx, :new, []), span_ctx])

      context
      |> inject_carrier()
      |> trace_from_carrier()
    end
  catch
    _, _ -> nil
  end

  @doc false
  @spec start([atom()], map(), map(), keyword()) :: Span.t() | nil
  def start(prefix, metadata, measurements, opts \\ [])
      when is_list(prefix) and is_map(metadata) and is_map(measurements) and is_list(opts) do
    if enabled?() do
      current_context = call(:otel_ctx, :get_current, [])
      parent_context = parent_context(opts, current_context)

      started_at =
        Keyword.get_lazy(opts, :start_time, fn -> call(:opentelemetry, :timestamp, []) end)

      span_ctx =
        call(:otel_tracer, :start_span, [
          parent_context,
          tracer(),
          span_name(prefix, metadata),
          %{
            attributes: attributes(metadata, measurements),
            kind: :internal,
            start_time: started_at
          }
        ])

      restore_context = activate_span(current_context, span_ctx)

      %Span{
        span_ctx: span_ctx,
        restore_context: restore_context,
        started_by: self(),
        terminal_guard: :atomics.new(1, signed: false)
      }
    end
  catch
    _, _ -> nil
  end

  @doc false
  @spec finish(Span.t() | nil, :stop | :exception, map(), map(), integer()) :: :ok
  def finish(nil, _ending, _metadata, _measurements, _ended_at), do: :ok

  def finish(%Span{} = span, ending, metadata, measurements, ended_at)
      when ending in [:stop, :exception] and is_map(metadata) and is_map(measurements) and
             is_integer(ended_at) do
    if claim_terminal?(span) do
      attrs = attributes(metadata, measurements) |> maybe_put_error_type(metadata)

      try do
        safely(fn -> call(:otel_span, :set_attributes, [span.span_ctx, attrs]) end)
        safely(fn -> maybe_record_exception(span.span_ctx, ending, metadata) end)
        safely(fn -> maybe_set_error_status(span.span_ctx, metadata) end)
        safely(fn -> call(:otel_span, :end_span, [span.span_ctx, ended_at]) end)
      after
        deactivate_span(span)
      end
    end

    :ok
  catch
    _, _ -> :ok
  end

  @doc false
  @spec point([atom()], map(), map(), keyword()) :: :ok
  def point(event, metadata, measurements, opts \\ [])
      when is_list(event) and is_map(metadata) and is_map(measurements) and is_list(opts) do
    if enabled?() do
      at = Keyword.get_lazy(opts, :at, fn -> call(:opentelemetry, :timestamp, []) end)
      parent_context = parent_context(opts, call(:otel_ctx, :get_current, []))

      start_opts = %{
        attributes: attributes(metadata, measurements) |> maybe_put_error_type(metadata),
        kind: :internal,
        start_time: at
      }

      start_opts = maybe_put_link(start_opts, Keyword.get(opts, :link_span))

      span_ctx =
        call(:otel_tracer, :start_span, [
          parent_context,
          tracer(),
          span_name(event, metadata),
          start_opts
        ])

      safely(fn -> maybe_set_error_status(span_ctx, metadata) end)
      safely(fn -> call(:otel_span, :end_span, [span_ctx, at]) end)
    end

    :ok
  catch
    _, _ -> :ok
  end

  @doc false
  @spec current_context() :: term() | nil
  def current_context do
    if enabled?(), do: call(:otel_ctx, :get_current, [])
  catch
    _, _ -> nil
  end

  @doc false
  @spec context_from_trace(map() | nil) :: term() | nil
  def context_from_trace(trace) when is_map(trace) do
    if enabled?() do
      case trace_carrier(trace) do
        [] ->
          nil

        carrier ->
          call(:otel_propagator_text_map, :extract_to, [
            call(:otel_ctx, :new, []),
            :otel_propagator_trace_context,
            carrier
          ])
      end
    end
  catch
    _, _ -> nil
  end

  def context_from_trace(_trace), do: nil

  @doc false
  @spec with_context(term() | nil, (-> result)) :: result when result: term()
  def with_context(nil, fun) when is_function(fun, 0), do: fun.()

  def with_context(context, fun) when is_function(fun, 0) do
    restore_context = call(:otel_ctx, :attach, [context])

    try do
      fun.()
    after
      _ = call(:otel_ctx, :detach, [restore_context])
    end
  end

  @doc false
  @spec restore_trace_context(map() | nil) :: term() | nil
  def restore_trace_context(trace) do
    case context_from_trace(trace) do
      nil -> nil
      context -> call(:otel_ctx, :attach, [context])
    end
  catch
    _, _ -> nil
  end

  @doc false
  @spec detach_trace_context(term() | nil) :: :ok
  def detach_trace_context(nil), do: :ok

  def detach_trace_context(restore_context) do
    _ = call(:otel_ctx, :detach, [restore_context])
    :ok
  catch
    _, _ -> :ok
  end

  defp available?, do: Code.ensure_loaded?(:opentelemetry)

  defp configured? do
    config = Application.get_env(:jido, :opentelemetry, [])
    config_value(config, :enabled, true) != false
  end

  defp tracer, do: call(:opentelemetry, :get_application_tracer, [__MODULE__])

  defp noop_tracer?({:otel_tracer_noop, _state}), do: true
  defp noop_tracer?(:otel_tracer_noop), do: true
  defp noop_tracer?(_tracer), do: false

  defp parent_context(opts, current) do
    case Keyword.get(opts, :parent_span) do
      %{otel: %Span{span_ctx: span_ctx}} ->
        call(:otel_tracer, :set_current_span, [current, span_ctx])

      %Span{span_ctx: span_ctx} ->
        call(:otel_tracer, :set_current_span, [current, span_ctx])

      _other ->
        current
    end
  end

  defp span_name(prefix, metadata) do
    segments = Enum.map(prefix, &Atom.to_string/1)

    segments =
      case {List.last(prefix), operation(metadata)} do
        {:lifecycle, operation} when is_atom(operation) ->
          segments ++ [Atom.to_string(operation)]

        {:operation, operation} when is_atom(operation) ->
          List.replace_at(segments, -1, Atom.to_string(operation))

        _other ->
          segments
      end

    Enum.join(segments, ".")
  end

  defp operation(%{operation: operation}), do: operation
  defp operation(%{topology_operation: operation}), do: operation
  defp operation(_metadata), do: nil

  defp attributes(metadata, measurements) do
    metadata
    |> Map.merge(Map.drop(measurements, @ignored_measurements))
    |> Enum.reduce(%{}, fn
      {_key, nil}, acc ->
        acc

      {key, value}, acc when is_atom(key) ->
        case attribute_value(value) do
          nil -> acc
          value -> Map.put(acc, attribute_key(key), value)
        end

      _field, acc ->
        acc
    end)
  end

  defp attribute_key(:schema_version), do: "jido.schema.version"
  defp attribute_key(:trace_id), do: "jido.trace.id"
  defp attribute_key(:span_id), do: "jido.span.id"
  defp attribute_key(:parent_span_id), do: "jido.parent_span.id"
  defp attribute_key(:error_type), do: "jido.error.type"
  defp attribute_key(:error_code), do: "jido.error.code"

  defp attribute_key(key) do
    key
    |> Atom.to_string()
    |> String.trim_trailing("?")
    |> String.replace("_", ".")
    |> then(&"jido.#{&1}")
  end

  defp attribute_value(value) when is_binary(value) or is_boolean(value) or is_integer(value),
    do: value

  defp attribute_value(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp attribute_value(_value), do: nil

  defp maybe_put_error_type(attributes, metadata) do
    case error_type(metadata) do
      nil -> attributes
      value -> Map.put(attributes, "error.type", value)
    end
  end

  defp error_type(%{status: status} = metadata) when status not in [:ok, :cancelled] do
    case Map.get(metadata, :error_code) || Map.get(metadata, :error_type) || status do
      value when is_atom(value) -> Atom.to_string(value)
      value when is_binary(value) -> value
      _value -> nil
    end
  end

  defp error_type(_metadata), do: nil

  defp maybe_set_error_status(span_ctx, metadata) do
    if error_type(metadata), do: call(:otel_span, :set_status, [span_ctx, :error]), else: false
  end

  defp maybe_record_exception(span_ctx, :exception, metadata) do
    attrs =
      %{}
      |> maybe_put("exception.type", error_type(metadata) || kind(metadata))
      |> maybe_put("jido.error.kind", kind(metadata))

    call(:otel_span, :add_event, [span_ctx, "exception", attrs])
  end

  defp maybe_record_exception(_span_ctx, :stop, _metadata), do: false

  defp kind(%{kind: kind}) when is_atom(kind), do: Atom.to_string(kind)
  defp kind(_metadata), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_link(opts, %Span{span_ctx: span_ctx}) do
    Map.put(opts, :links, [call(:opentelemetry, :link, [span_ctx])])
  end

  defp maybe_put_link(opts, %{otel: %Span{span_ctx: span_ctx}}) do
    Map.put(opts, :links, [call(:opentelemetry, :link, [span_ctx])])
  end

  defp maybe_put_link(opts, _span), do: opts

  defp claim_terminal?(%Span{terminal_guard: guard}) do
    :atomics.compare_exchange(guard, 1, 0, 1) == :ok
  end

  defp activate_span(parent_context, span_ctx) do
    active_context = call(:otel_tracer, :set_current_span, [parent_context, span_ctx])
    call(:otel_ctx, :attach, [active_context])
  end

  defp deactivate_span(%Span{started_by: pid, restore_context: restore_context})
       when pid == self() do
    _ = call(:otel_ctx, :detach, [restore_context])
    :ok
  end

  defp deactivate_span(_span), do: :ok

  defp trace_carrier(trace) do
    []
    |> maybe_add_carrier("traceparent", Map.get(trace, :traceparent))
    |> maybe_add_carrier("tracestate", Map.get(trace, :tracestate))
  end

  defp maybe_add_carrier(carrier, _key, nil), do: carrier

  defp maybe_add_carrier(carrier, key, value) when is_binary(value),
    do: [{key, value} | carrier]

  defp maybe_add_carrier(carrier, _key, _value), do: carrier

  defp inject_carrier(context) do
    call(:otel_propagator_text_map, :inject_from, [
      context,
      :otel_propagator_trace_context,
      []
    ])
  end

  defp trace_from_carrier(carrier) do
    fields =
      Enum.reduce(carrier, %{}, fn
        {key, value}, acc when is_binary(key) and is_binary(value) ->
          case String.downcase(key) do
            "traceparent" -> Map.put(acc, :traceparent, value)
            "tracestate" -> Map.put(acc, :tracestate, value)
            _other -> acc
          end

        _field, acc ->
          acc
      end)

    case SignalTrace.from_traceparent(fields[:traceparent], fields[:tracestate]) do
      {:ok, trace} ->
        %{
          trace_id: trace.trace_id,
          span_id: trace.span_id,
          trace_flags: trace.trace_flags,
          traceparent: SignalTrace.to_traceparent(trace)
        }
        |> maybe_put(:tracestate, trace.tracestate)

      {:error, :invalid_traceparent} ->
        nil
    end
  end

  defp safely(fun) do
    fun.()
  rescue
    _error -> false
  catch
    _kind, _reason -> false
  end

  defp call(module, function, arguments), do: apply(module, function, arguments)

  defp config_value(config, key, default) when is_list(config),
    do: Keyword.get(config, key, default)

  defp config_value(config, key, default) when is_map(config), do: Map.get(config, key, default)
  defp config_value(_config, _key, default), do: default
end
