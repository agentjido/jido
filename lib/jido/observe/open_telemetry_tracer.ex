defmodule Jido.Observe.OpenTelemetryTracer do
  @moduledoc """
  First-party OpenTelemetry tracer for `Jido.Observe`.

  This tracer integrates with OpenTelemetry when the optional `:opentelemetry`
  and `:opentelemetry_api` dependencies are available at runtime. If they are
  not present, callbacks safely no-op and return `:ok`/`nil`.
  """

  @behaviour Jido.Observe.Tracer

  require Logger

  @config_key :open_telemetry_tracer_modules
  @default_modules %{
    opentelemetry: :opentelemetry,
    otel_tracer: :otel_tracer,
    otel_span: :otel_span
  }

  @type otel_modules :: %{
          opentelemetry: module(),
          otel_tracer: module(),
          otel_span: module()
        }

  @type tctx :: %{
          span_ctx: term(),
          parent_ctx: term(),
          modules: otel_modules()
        }

  @impl true
  @spec span_start(Jido.Observe.Tracer.event_prefix(), Jido.Observe.Tracer.metadata()) ::
          tctx() | nil
  def span_start(event_prefix, metadata) when is_list(event_prefix) and is_map(metadata) do
    with {:ok, modules} <- resolve_modules(),
         {:ok, tracer} <- application_tracer(modules.opentelemetry),
         span_name <- Enum.join(event_prefix, "."),
         parent_ctx <- current_span_ctx(modules.otel_tracer),
         span_ctx <- start_span(modules.otel_tracer, tracer, span_name, metadata),
         false <- is_nil(span_ctx) do
      _ = set_current_span(modules.otel_tracer, span_ctx)
      %{span_ctx: span_ctx, parent_ctx: parent_ctx, modules: modules}
    else
      _ -> nil
    end
  rescue
    exception ->
      Logger.warning(
        "Jido.Observe.OpenTelemetryTracer span_start/2 failed: #{Exception.message(exception)}"
      )

      nil
  end

  @impl true
  @spec span_stop(Jido.Observe.Tracer.tracer_ctx(), Jido.Observe.Tracer.measurements()) :: :ok
  def span_stop(%{span_ctx: span_ctx, parent_ctx: parent_ctx, modules: modules}, measurements)
      when is_map(measurements) do
    measurements
    |> Map.put_new(:duration_ms, duration_ms(measurements))
    |> normalize_attributes()
    |> set_span_attributes(modules.otel_span, span_ctx)

    _ = end_span(modules.otel_span, span_ctx)
    _ = restore_parent_span(modules.otel_tracer, parent_ctx)
    :ok
  rescue
    exception ->
      Logger.warning(
        "Jido.Observe.OpenTelemetryTracer span_stop/2 failed: #{Exception.message(exception)}"
      )

      :ok
  end

  def span_stop(_tracer_ctx, _measurements), do: :ok

  @impl true
  @spec span_exception(Jido.Observe.Tracer.tracer_ctx(), atom(), term(), list()) :: :ok
  def span_exception(
        %{span_ctx: span_ctx, parent_ctx: parent_ctx, modules: modules},
        kind,
        reason,
        stacktrace
      )
      when is_atom(kind) and is_list(stacktrace) do
    _ = set_status(modules.otel_span, span_ctx, :error, format_reason(kind, reason))
    _ = record_exception(modules.otel_span, span_ctx, kind, reason, stacktrace)
    _ = end_span(modules.otel_span, span_ctx)
    _ = restore_parent_span(modules.otel_tracer, parent_ctx)
    :ok
  rescue
    exception ->
      Logger.warning(
        "Jido.Observe.OpenTelemetryTracer span_exception/4 failed: #{Exception.message(exception)}"
      )

      :ok
  end

  def span_exception(_tracer_ctx, _kind, _reason, _stacktrace), do: :ok

  defp resolve_modules do
    configured = Application.get_env(:jido, @config_key, %{})

    modules = %{
      opentelemetry: Map.get(configured, :opentelemetry, @default_modules.opentelemetry),
      otel_tracer: Map.get(configured, :otel_tracer, @default_modules.otel_tracer),
      otel_span: Map.get(configured, :otel_span, @default_modules.otel_span)
    }

    if module_available?(modules.opentelemetry, :get_application_tracer, 1) and
         (module_available?(modules.otel_tracer, :start_span, 3) or
            module_available?(modules.otel_tracer, :start_span, 2)) and
         module_available?(modules.otel_span, :end_span, 1) do
      {:ok, modules}
    else
      {:error, :otel_unavailable}
    end
  end

  defp module_available?(module, function, arity) do
    Code.ensure_loaded?(module) and function_exported?(module, function, arity)
  end

  defp application_tracer(opentelemetry_module) do
    tracer = apply(opentelemetry_module, :get_application_tracer, [:jido])
    {:ok, tracer}
  rescue
    _exception -> {:error, :missing_application_tracer}
  end

  defp current_span_ctx(otel_tracer_module) do
    if function_exported?(otel_tracer_module, :current_span_ctx, 0) do
      apply(otel_tracer_module, :current_span_ctx, [])
    end
  rescue
    _exception -> nil
  end

  defp set_current_span(otel_tracer_module, span_ctx) do
    if function_exported?(otel_tracer_module, :set_current_span, 1) do
      apply(otel_tracer_module, :set_current_span, [span_ctx])
    end
  rescue
    _exception -> :ok
  end

  defp restore_parent_span(_otel_tracer_module, nil), do: :ok

  defp restore_parent_span(otel_tracer_module, parent_ctx) do
    set_current_span(otel_tracer_module, parent_ctx)
  end

  defp start_span(otel_tracer_module, tracer, span_name, metadata) do
    opts = %{attributes: metadata |> normalize_attributes() |> Map.to_list()}

    result =
      cond do
        function_exported?(otel_tracer_module, :start_span, 3) ->
          apply(otel_tracer_module, :start_span, [tracer, span_name, opts])

        function_exported?(otel_tracer_module, :start_span, 2) ->
          apply(otel_tracer_module, :start_span, [span_name, opts])

        true ->
          nil
      end

    normalize_span_ctx(result)
  rescue
    _exception -> nil
  end

  defp normalize_span_ctx({span_ctx, _}) when not is_nil(span_ctx), do: span_ctx
  defp normalize_span_ctx(span_ctx) when span_ctx in [nil, false], do: nil
  defp normalize_span_ctx(span_ctx), do: span_ctx

  defp end_span(otel_span_module, span_ctx) do
    apply(otel_span_module, :end_span, [span_ctx])
  rescue
    _exception -> :ok
  end

  defp set_span_attributes(attributes, _otel_span_module, _span_ctx)
       when map_size(attributes) == 0,
       do: :ok

  defp set_span_attributes(attributes, otel_span_module, span_ctx) do
    cond do
      function_exported?(otel_span_module, :set_attributes, 2) ->
        apply(otel_span_module, :set_attributes, [span_ctx, Map.to_list(attributes)])

      function_exported?(otel_span_module, :set_attribute, 3) ->
        Enum.each(attributes, fn {key, value} ->
          apply(otel_span_module, :set_attribute, [span_ctx, key, value])
        end)

      true ->
        :ok
    end
  rescue
    _exception -> :ok
  end

  defp set_status(otel_span_module, span_ctx, status, message) do
    cond do
      function_exported?(otel_span_module, :set_status, 3) ->
        apply(otel_span_module, :set_status, [span_ctx, status, message])

      function_exported?(otel_span_module, :set_status, 2) ->
        apply(otel_span_module, :set_status, [span_ctx, {status, message}])

      true ->
        :ok
    end
  rescue
    _exception -> :ok
  end

  defp record_exception(otel_span_module, span_ctx, kind, reason, stacktrace) do
    attrs = %{"jido.kind" => Atom.to_string(kind)} |> Map.to_list()

    cond do
      function_exported?(otel_span_module, :record_exception, 5) ->
        apply(otel_span_module, :record_exception, [span_ctx, kind, reason, stacktrace, attrs])

      function_exported?(otel_span_module, :record_exception, 4) ->
        apply(otel_span_module, :record_exception, [span_ctx, reason, stacktrace, attrs])

      true ->
        :ok
    end
  rescue
    _exception -> :ok
  end

  defp duration_ms(%{duration: duration}) when is_integer(duration) and duration >= 0 do
    System.convert_time_unit(duration, :nanosecond, :millisecond)
  end

  defp duration_ms(_measurements), do: 0

  defp format_reason(kind, reason) do
    "#{kind}: #{inspect(reason)}"
  end

  defp normalize_attributes(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      case normalize_attribute_value(value) do
        nil ->
          acc

        normalized ->
          Map.put(acc, normalize_attribute_key(key), normalized)
      end
    end)
  end

  defp normalize_attribute_key(key) when is_binary(key), do: key
  defp normalize_attribute_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_attribute_key(key), do: inspect(key)

  defp normalize_attribute_value(value) when is_binary(value), do: value
  defp normalize_attribute_value(value) when is_boolean(value), do: value
  defp normalize_attribute_value(value) when is_integer(value), do: value
  defp normalize_attribute_value(value) when is_float(value), do: value
  defp normalize_attribute_value(value) when is_nil(value), do: nil
  defp normalize_attribute_value(value) when is_atom(value), do: Atom.to_string(value)

  defp normalize_attribute_value(value) when is_list(value) do
    value
    |> Enum.map(&normalize_attribute_value/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_attribute_value(value), do: inspect(value, limit: 100)
end
