defmodule Jido.Signal.Dispatch do
  alias Jido.Joi

  @moduledoc """
  Validates dispatch targets and delivers Signals.

  Dispatch is synchronous. A target is an `{adapter, options}` tuple. A list of
  targets is delivered in registration order. The caller owns asynchronous work,
  retries, concurrency limits, and circuit breaking.

  Built-in adapters are `:pid`, `:named`, `:pubsub`, `:bus`, `:logger`,
  `:noop`, and `:http`. The `:named` input uses the process adapter. The
  `:noop` input has no adapter module. A custom adapter can implement
  `Jido.Signal.Dispatch.Adapter`.
  """

  defmodule Target do
    @moduledoc false

    @enforce_keys [:adapter, :module, :opts]
    defstruct [:adapter, :module, :opts]

    @type t :: %__MODULE__{
            adapter: Jido.Signal.Dispatch.adapter(),
            module: module() | nil,
            opts: keyword()
          }

    @doc false
    @spec to_tuple(t()) :: {atom(), keyword()}
    def to_tuple(%__MODULE__{adapter: adapter, opts: opts}), do: {adapter, opts}
  end

  alias __MODULE__.Target
  alias Jido.Signal.Error
  alias Jido.Signal.Sanitizer
  alias Jido.Telemetry.Signal, as: Telemetry

  @type adapter ::
          :pid
          | :bus
          | :named
          | :pubsub
          | :logger
          | :noop
          | :http
          | nil
          | module()
  @type dispatch_config :: {adapter(), keyword()}
  @type dispatch_configs :: dispatch_config() | [dispatch_config()]

  @normalize_errors_compile_time Application.compile_env(
                                   :jido,
                                   :normalize_dispatch_errors,
                                   false
                                 )

  @builtin_adapters %{
    pid: Jido.Signal.Dispatch.PidAdapter,
    named: Jido.Signal.Dispatch.PidAdapter,
    pubsub: Jido.Signal.Dispatch.PubSub,
    bus: Jido.Signal.Dispatch.Bus,
    logger: Jido.Signal.Dispatch.LoggerAdapter,
    noop: nil,
    http: Jido.Signal.Dispatch.Http
  }

  @noop_options_schema Joi.keyword([], unrecognized_keys: :error)

  @doc """
  Validates one target tuple or a list of target tuples.

  The return value keeps the public tuple form. Dispatch uses an internal Target
  value after this boundary.
  """
  @spec validate_opts(dispatch_configs()) :: {:ok, dispatch_configs()} | {:error, term()}
  def validate_opts({adapter, opts}) when is_atom(adapter) and is_list(opts) do
    with {:ok, target} <- normalize_target({adapter, opts}) do
      {:ok, Target.to_tuple(target)}
    end
  end

  def validate_opts(configs) when is_list(configs) and is_integer(length(configs)) do
    configs
    |> Enum.reduce_while({:ok, []}, fn config, {:ok, targets} ->
      case normalize_target(config) do
        {:ok, target} -> {:cont, {:ok, [Target.to_tuple(target) | targets]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, targets} -> {:ok, Enum.reverse(targets)}
      error -> error
    end
  end

  def validate_opts(invalid_config), do: invalid_dispatch_config(invalid_config)

  @doc """
  Delivers a Signal to one target or a list of targets.

  A single target returns `:ok` or `{:error, reason}`. A target list returns
  `:ok` or `{:error, reasons}`. List delivery is synchronous and ordered.
  """
  @spec dispatch(Jido.Signal.t(), dispatch_configs()) :: :ok | {:error, term()}
  def dispatch(signal, {adapter, opts} = config) when is_atom(adapter) and is_list(opts) do
    with {:ok, target} <- normalize_target(config) do
      deliver(signal, target)
    end
  end

  def dispatch(signal, configs) when is_list(configs) and is_integer(length(configs)) do
    errors =
      Enum.reduce(configs, [], fn config, errors ->
        result =
          with {:ok, target} <- normalize_target(config) do
            deliver(signal, target)
          end

        case result do
          :ok -> errors
          {:error, reason} -> [reason | errors]
        end
      end)

    case Enum.reverse(errors) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  def dispatch(_signal, invalid_config), do: invalid_dispatch_config(invalid_config)

  defp normalize_target({nil, opts}) when is_list(opts) do
    if Keyword.keyword?(opts),
      do: {:ok, %Target{adapter: nil, module: nil, opts: strip_internal_opts(opts)}},
      else: invalid_dispatch_config({nil, opts})
  end

  defp normalize_target({adapter, opts} = config) when is_atom(adapter) and is_list(opts) do
    if Keyword.keyword?(opts) do
      opts = strip_internal_opts(opts)

      with {:ok, adapter_module} <- resolve_adapter(adapter),
           {:ok, validated_opts} <- parse_adapter_options(adapter_module, opts) do
        {:ok, %Target{adapter: adapter, module: adapter_module, opts: validated_opts}}
      else
        {:error, reason} -> normalize_validation_error(reason, adapter, config)
      end
    else
      invalid_dispatch_config(config)
    end
  end

  defp normalize_target(invalid_config), do: invalid_dispatch_config(invalid_config)

  defp deliver(_signal, %Target{adapter: nil}), do: :ok

  defp deliver(signal, %Target{adapter: :noop} = target) do
    with_dispatch_telemetry(signal, target, fn -> :ok end)
  end

  defp deliver(signal, %Target{} = target) do
    with_dispatch_telemetry(signal, target, fn ->
      case target.module.deliver(signal, target.opts) do
        :ok -> :ok
        {:error, reason} -> normalize_error(reason, target.adapter, Target.to_tuple(target))
      end
    end)
  end

  defp with_dispatch_telemetry(signal, target, fun) do
    start_time = System.monotonic_time(:millisecond)
    metadata = dispatch_telemetry_metadata(signal, target)
    Telemetry.execute([:jido, :dispatch, :start], %{}, metadata, signal)

    result =
      try do
        fun.()
      catch
        kind, reason ->
          Telemetry.execute(
            [:jido, :dispatch, :exception],
            dispatch_latency(start_time),
            Map.merge(metadata, %{
              outcome: :raised,
              success?: false,
              error_type: :dispatch_error,
              retryable?: false,
              exception_kind: kind,
              exception_module: exception_module(reason)
            }),
            signal
          )

          :erlang.raise(kind, reason, __STACKTRACE__)
      end

    measurements = dispatch_latency(start_time)

    case result do
      :ok ->
        Telemetry.execute(
          [:jido, :dispatch, :stop],
          measurements,
          Map.merge(metadata, %{outcome: :ok, success?: true}),
          signal
        )

      {:error, reason} ->
        error = dispatch_error_for_telemetry(reason, target)

        Telemetry.execute(
          [:jido, :dispatch, :exception],
          measurements,
          Map.merge(metadata, %{
            outcome: :error,
            success?: false,
            error_type: Error.type(error),
            retryable?: Error.retryable?(error)
          }),
          signal
        )
    end

    result
  end

  defp dispatch_latency(start_time) do
    %{latency_ms: System.monotonic_time(:millisecond) - start_time}
  end

  defp exception_module(%{__exception__: true, __struct__: module}) when is_atom(module),
    do: module

  defp exception_module(_reason), do: :unknown

  defp dispatch_telemetry_metadata(signal, target) do
    %{
      adapter: target.adapter,
      runtime_surface: :dispatch,
      signal_type: signal_type(signal),
      target: get_target_from_opts(target.adapter, target.opts),
      target_kind: target_kind(target.adapter, target.opts)
    }
  end

  defp signal_type(%{type: type}) when is_binary(type), do: Sanitizer.sanitize(type, :telemetry)
  defp signal_type(_signal), do: :unknown

  defp get_target_from_opts(:pubsub, opts) do
    opts
    |> Keyword.get(:topic, :unknown)
    |> Sanitizer.sanitize(:telemetry)
  end

  defp get_target_from_opts(_adapter, opts) do
    cond do
      url = Keyword.get(opts, :url) -> url_target_for_telemetry(url)
      target = Keyword.get(opts, :target) -> Sanitizer.sanitize(target, :telemetry)
      pid = Keyword.get(opts, :pid) -> Sanitizer.sanitize(pid, :telemetry)
      name = Keyword.get(opts, :name) -> Sanitizer.sanitize(name, :telemetry)
      topic = Keyword.get(opts, :topic) -> Sanitizer.sanitize(topic, :telemetry)
      true -> :unknown
    end
  end

  defp url_target_for_telemetry(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host} = uri}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        %URI{scheme: uri.scheme, host: uri.host, port: uri.port}
        |> URI.to_string()
        |> Sanitizer.sanitize(:telemetry)

      _ ->
        :invalid_url
    end
  end

  defp url_target_for_telemetry(_url), do: :invalid_url

  defp target_kind(:pubsub, _opts), do: :topic

  defp target_kind(_adapter, opts) do
    cond do
      Keyword.has_key?(opts, :url) -> :url
      Keyword.has_key?(opts, :topic) -> :topic
      Keyword.has_key?(opts, :pid) -> :pid
      match?({:name, _}, Keyword.get(opts, :target)) -> :name
      is_pid(Keyword.get(opts, :target)) -> :pid
      Keyword.has_key?(opts, :target) -> :target
      true -> :unknown
    end
  end

  defp resolve_adapter(adapter) when is_atom(adapter) do
    case Map.fetch(@builtin_adapters, adapter) do
      {:ok, module} ->
        {:ok, module}

      :error ->
        if dispatch_adapter_module?(adapter) do
          {:ok, adapter}
        else
          {:error, invalid_adapter_message(adapter)}
        end
    end
  end

  defp dispatch_adapter_module?(adapter) do
    Code.ensure_loaded?(adapter) and
      function_exported?(adapter, :options_schema, 0) and
      function_exported?(adapter, :deliver, 2) and
      Enum.any?(adapter.module_info(:attributes), fn {key, values} ->
        key == :behaviour and Jido.Signal.Dispatch.Adapter in values
      end)
  rescue
    _ -> false
  end

  defp invalid_adapter_message(adapter) do
    "#{inspect(adapter)} is not a valid adapter - must be one of :pid, :named, " <>
      ":pubsub, :bus, :logger, :noop, :http or a module " <>
      "implementing Jido.Signal.Dispatch.Adapter"
  end

  defp parse_adapter_options(nil, opts), do: parse_options(@noop_options_schema, opts)

  defp parse_adapter_options(adapter_module, opts) do
    schema = adapter_module.options_schema()

    if Joi.Schema.schema?(schema) do
      parse_options(schema, opts)
    else
      {:error, {:invalid_options_schema, adapter_module}}
    end
  rescue
    error -> {:error, {:invalid_options_schema, Exception.message(error)}}
  end

  defp parse_options(schema, opts) do
    case Joi.parse(schema, opts) do
      {:ok, validated_opts} -> {:ok, validated_opts}
      {:error, errors} -> {:error, Joi.prettify_errors(errors)}
    end
  end

  defp strip_internal_opts(opts), do: Keyword.delete(opts, :__validated__)

  defp invalid_dispatch_config(invalid_config) do
    if should_normalize_errors?() do
      {:error,
       Error.validation_error("Invalid dispatch configuration", %{
         field: "dispatch_config",
         value: dispatch_config_shape(invalid_config),
         reason: :invalid_dispatch_config
       })}
    else
      {:error, :invalid_dispatch_config}
    end
  end

  defp dispatch_config_shape(value) when is_map(value),
    do: %{type: :map, size: map_size(value)}

  defp dispatch_config_shape(value) when is_list(value) and is_integer(length(value)),
    do: %{type: :list, count: length(value)}

  defp dispatch_config_shape(value) when is_list(value), do: %{type: :improper_list}

  defp dispatch_config_shape(value) when is_tuple(value),
    do: %{type: :tuple, size: tuple_size(value)}

  defp dispatch_config_shape(value) when is_binary(value),
    do: %{type: :binary, bytes: byte_size(value)}

  defp dispatch_config_shape(value) when is_atom(value), do: %{type: :atom}
  defp dispatch_config_shape(value) when is_number(value), do: %{type: :number}
  defp dispatch_config_shape(_value), do: %{type: :other}

  defp normalize_error(reason, adapter, config) do
    if should_normalize_errors?() do
      {:error,
       Error.dispatch_error("Signal dispatch failed", %{
         adapter: adapter,
         reason: reason,
         target: target_summary(adapter, config)
       })}
    else
      {:error, reason}
    end
  end

  defp normalize_validation_error(reason, adapter, config) do
    if should_normalize_errors?() do
      {:error,
       Error.validation_error("Invalid adapter configuration", %{
         field: "config",
         adapter: adapter,
         reason: reason,
         target: target_summary(adapter, config)
       })}
    else
      {:error, reason}
    end
  end

  defp should_normalize_errors? do
    Application.get_env(:jido, :normalize_dispatch_errors, @normalize_errors_compile_time)
  end

  defp dispatch_error_for_telemetry(%Error.DispatchError{} = error, _target), do: error

  defp dispatch_error_for_telemetry(reason, target) do
    Error.dispatch_error("Signal dispatch failed", %{
      adapter: target.adapter,
      reason: reason,
      target: target_summary(target.adapter, Target.to_tuple(target))
    })
  end

  defp target_summary(adapter, {_configured_adapter, opts}) when is_list(opts) do
    %{
      adapter: adapter,
      target: get_target_from_opts(adapter, opts),
      target_kind: target_kind(adapter, opts)
    }
  end

  defp target_summary(adapter, _config), do: %{adapter: adapter}
end
