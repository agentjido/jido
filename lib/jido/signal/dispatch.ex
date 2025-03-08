defmodule Jido.Signal.Dispatch do
  @moduledoc """
  A flexible signal dispatching system that routes signals to various destinations using configurable adapters.

  The Dispatch module serves as the central hub for signal delivery in the Jido system. It provides a unified
  interface for sending signals to different destinations through various adapters. Each adapter implements
  specific delivery mechanisms suited for different use cases.

  ## Built-in Adapters

  The following adapters are provided out of the box:

  * `:pid` - Direct delivery to a specific process (see `Jido.Signal.Dispatch.PidAdapter`)
  * `:bus` - Delivery to an event bus (see `Jido.Signal.Dispatch.Bus`)
  * `:named` - Delivery to a named process (see `Jido.Signal.Dispatch.Named`)
  * `:pubsub` - Delivery via PubSub mechanism (see `Jido.Signal.Dispatch.PubSub`)
  * `:logger` - Log signals using Logger (see `Jido.Signal.Dispatch.LoggerAdapter`)
  * `:console` - Print signals to console (see `Jido.Signal.Dispatch.ConsoleAdapter`)
  * `:noop` - No-op adapter for testing/development (see `Jido.Signal.Dispatch.NoopAdapter`)
  * `:http` - HTTP requests using :httpc (see `Jido.Signal.Dispatch.Http`)
  * `:webhook` - Webhook delivery with signatures (see `Jido.Signal.Dispatch.Webhook`)

  ## Configuration

  Each adapter requires specific configuration options. A dispatch configuration is a tuple of
  `{adapter_type, options}` where:

  * `adapter_type` - One of the built-in adapter types above or a custom module implementing the `Jido.Signal.Dispatch.Adapter` behaviour
  * `options` - Keyword list of options specific to the chosen adapter

  Multiple dispatch configurations can be provided as a list to send signals to multiple destinations.

  ## Dispatch Modes

  The module supports three dispatch modes:

  1. Synchronous (via `dispatch/2`) - Fire-and-forget dispatch that returns when all dispatches complete
  2. Asynchronous (via `dispatch_async/2`) - Returns immediately with a task that can be monitored
  3. Batched (via `dispatch_batch/3`) - Handles large numbers of dispatches in configurable batches

  ## Examples

      # Synchronous dispatch
      config = {:pid, [target: pid, delivery_mode: :async]}
      :ok = Dispatch.dispatch(signal, config)

      # Asynchronous dispatch
      {:ok, task} = Dispatch.dispatch_async(signal, config)
      :ok = Task.await(task)

      # Batch dispatch
      configs = List.duplicate({:pid, [target: pid]}, 1000)
      :ok = Dispatch.dispatch_batch(signal, configs, batch_size: 100)

      # HTTP dispatch
      config = {:http, [
        url: "https://api.example.com/events",
        method: :post,
        headers: [{"x-api-key", "secret"}]
      ]}
      :ok = Dispatch.dispatch(signal, config)

      # Webhook dispatch
      config = {:webhook, [
        url: "https://api.example.com/webhook",
        secret: "webhook_secret",
        event_type_map: %{"user:created" => "user.created"}
      ]}
      :ok = Dispatch.dispatch(signal, config)
  """

  @type adapter ::
          :pid
          | :bus
          | :named
          | :pubsub
          | :logger
          | :console
          | :noop
          | :http
          | :webhook
          | nil
          | module()
  @type dispatch_config :: {adapter(), Keyword.t()}
  @type dispatch_configs :: dispatch_config() | [dispatch_config()]
  @type batch_opts :: [
          batch_size: pos_integer(),
          max_concurrency: pos_integer()
        ]

  @default_batch_size 50
  @default_max_concurrency 5

  @builtin_adapters %{
    pid: Jido.Signal.Dispatch.PidAdapter,
    bus: Jido.Signal.Dispatch.Bus,
    named: Jido.Signal.Dispatch.Named,
    pubsub: Jido.Signal.Dispatch.PubSub,
    logger: Jido.Signal.Dispatch.LoggerAdapter,
    console: Jido.Signal.Dispatch.ConsoleAdapter,
    noop: Jido.Signal.Dispatch.NoopAdapter,
    http: Jido.Signal.Dispatch.Http,
    webhook: Jido.Signal.Dispatch.Webhook,
    nil: nil
  }

  # Future Idea
  # use TypedStruct

  # typedstruct do
  #   @typedoc "A dispatch configuration for sending signals"

  #   field :signals, Jido.Signal.t() | [Jido.Signal.t()], default: [], doc: "List of signals to be dispatched"
  #   field :targets, [dispatch_config()], default: [], doc: "List of dispatch_config tuples"
  #   field :mode, :sync | :async, default: :sync, doc: ":sync or :async"
  #   field :opts, Keyword.t(), default: [], doc: "General options including batch settings"
  #   field :validated, boolean(), default: false, doc: "Whether targets have been validated"
  # end

  @doc """
  Validates a dispatch configuration.

  ## Parameters

  - `config` - Either a single dispatch configuration tuple or a list of dispatch configurations

  ## Returns

  - `{:ok, config}` if the configuration is valid
  - `{:error, reason}` if the configuration is invalid

  ## Examples

      # Single config
      iex> config = {:pid, [target: {:pid, self()}, delivery_mode: :async]}
      iex> Jido.Signal.Dispatch.validate_opts(config)
      {:ok, ^config}

      # Multiple configs
      iex> config = [
      ...>   {:bus, [target: {:bus, :default}, stream: "events"]},
      ...>   {:pubsub, [target: {:pubsub, :audit}, topic: "audit"]}
      ...> ]
      iex> Jido.Signal.Dispatch.validate_opts(config)
      {:ok, ^config}
  """
  @spec validate_opts(dispatch_configs()) :: {:ok, dispatch_configs()} | {:error, term()}
  # Handle single dispatcher config
  def validate_opts(config = {adapter, opts}) when is_atom(adapter) and is_list(opts) do
    validate_single_config(config)
  end

  # Handle list of dispatchers
  def validate_opts(configs) when is_list(configs) do
    results = Enum.map(configs, &validate_single_config/1)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, value} -> value end)}
      error -> error
    end
  end

  def validate_opts(_), do: {:error, :invalid_dispatch_config}

  @doc """
  Dispatches a signal using the provided configuration.

  This is a synchronous operation that returns when all dispatches complete.
  For asynchronous dispatch, use `dispatch_async/2`.
  For batch dispatch, use `dispatch_batch/3`.

  ## Parameters

  - `signal` - The signal to dispatch
  - `config` - Either a single dispatch configuration tuple or a list of configurations

  ## Examples

      # Single destination
      iex> config = {:pid, [target: {:pid, pid}, delivery_mode: :async]}
      iex> Jido.Signal.Dispatch.dispatch(signal, config)
      :ok

      # Multiple destinations
      iex> config = [
      ...>   {:bus, [target: {:bus, :default}, stream: "events"]},
      ...>   {:pubsub, [target: :audit, topic: "audit"]}
      ...> ]
      iex> Jido.Signal.Dispatch.dispatch(signal, config)
      :ok
  """
  @spec dispatch(Jido.Signal.t(), dispatch_configs()) :: :ok | {:error, term()}
  # Handle single dispatcher
  def dispatch(signal, config = {adapter, opts}) when is_atom(adapter) and is_list(opts) do
    dispatch_single(signal, config)
  end

  # Handle multiple dispatchers
  def dispatch(signal, configs) when is_list(configs) do
    results = Enum.map(configs, &dispatch_single(signal, &1))

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end

  def dispatch(_signal, _config) do
    {:error, :invalid_dispatch_config}
  end

  @doc """
  Dispatches a signal asynchronously using the provided configuration.

  Returns immediately with a task that can be monitored for completion.

  ## Parameters

  - `signal` - The signal to dispatch
  - `config` - Either a single dispatch configuration tuple or a list of configurations

  ## Returns

  - `{:ok, task}` where task is a Task that can be awaited
  - `{:error, reason}` if the configuration is invalid

  ## Examples

      {:ok, task} = Dispatch.dispatch_async(signal, config)
      :ok = Task.await(task)
  """
  @spec dispatch_async(Jido.Signal.t(), dispatch_configs()) :: {:ok, Task.t()} | {:error, term()}
  def dispatch_async(signal, config) do
    case validate_opts(config) do
      {:ok, validated_config} ->
        task = Task.async(fn -> dispatch(signal, validated_config) end)
        {:ok, task}

      error ->
        error
    end
  end

  @doc """
  Dispatches a signal to multiple destinations in batches.

  This is useful when dispatching to a large number of destinations to avoid
  overwhelming the system. The dispatches are processed in batches of configurable
  size with configurable concurrency.

  ## Parameters

  - `signal` - The signal to dispatch
  - `configs` - List of dispatch configurations
  - `opts` - Batch options:
    * `:batch_size` - Size of each batch (default: #{@default_batch_size})
    * `:max_concurrency` - Maximum number of concurrent batches (default: #{@default_max_concurrency})

  ## Returns

  - `:ok` if all dispatches succeed
  - `{:error, errors}` where errors is a list of `{index, reason}` tuples

  ## Examples

      configs = List.duplicate({:pid, [target: pid]}, 1000)
      :ok = Dispatch.dispatch_batch(signal, configs, batch_size: 100)
  """
  @spec dispatch_batch(Jido.Signal.t(), [dispatch_config()], batch_opts()) ::
          :ok | {:error, [{non_neg_integer(), term()}]}
  def dispatch_batch(signal, configs, opts \\ []) when is_list(configs) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)

    # First validate all configs and track their indices
    configs_with_index = Enum.with_index(configs)

    validation_results =
      Enum.map(configs_with_index, fn {config, idx} ->
        case validate_opts(config) do
          {:ok, validated_config} -> {:ok, {validated_config, idx}}
          {:error, reason} -> {:error, {idx, reason}}
        end
      end)

    # Separate valid and invalid configs
    {valid_configs, validation_errors} =
      Enum.split_with(validation_results, fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    # Extract just the configs from valid results
    validated_configs = Enum.map(valid_configs, fn {:ok, {config, _}} -> config end)

    # Process valid configs in batches
    dispatch_results =
      if validated_configs != [] do
        batches = Enum.chunk_every(validated_configs, batch_size)

        Task.async_stream(
          batches,
          fn batch ->
            Enum.map(batch, fn config ->
              dispatch_single(signal, config)
            end)
          end,
          max_concurrency: max_concurrency,
          ordered: true
        )
        |> Enum.flat_map(fn {:ok, batch_results} -> batch_results end)
      else
        []
      end

    # Extract validation errors
    validation_errors = Enum.map(validation_errors, fn {:error, error} -> error end)

    # Check for dispatch errors
    dispatch_errors =
      Enum.with_index(dispatch_results)
      |> Enum.reduce([], fn
        {{:error, reason}, idx}, acc -> [{idx, reason} | acc]
        {:ok, _}, acc -> acc
      end)

    case {validation_errors, dispatch_errors} do
      {[], []} -> :ok
      {errors, []} -> {:error, Enum.reverse(errors)}
      {[], errors} -> {:error, Enum.reverse(errors)}
      {val_errs, disp_errs} -> {:error, Enum.reverse(val_errs ++ disp_errs)}
    end
  end

  # Private helpers

  defp validate_single_config({nil, opts}) when is_list(opts) do
    {:ok, {nil, opts}}
  end

  defp validate_single_config({adapter, opts}) when is_atom(adapter) and is_list(opts) do
    with {:ok, adapter_module} <- resolve_adapter(adapter),
         {:ok, validated_opts} <- adapter_module.validate_opts(opts) do
      {:ok, {adapter, validated_opts}}
    end
  end

  defp dispatch_single(_signal, {nil, _opts}), do: :ok

  defp dispatch_single(signal, {adapter, opts}) do
    with {:ok, adapter_module} <- resolve_adapter(adapter),
         {:ok, validated_opts} <- adapter_module.validate_opts(opts) do
      adapter_module.deliver(signal, validated_opts)
    end
  end

  defp resolve_adapter(nil), do: {:error, :no_adapter_needed}

  defp resolve_adapter(adapter) when is_atom(adapter) do
    case Map.fetch(@builtin_adapters, adapter) do
      {:ok, module} when not is_nil(module) ->
        {:ok, module}

      {:ok, nil} ->
        {:error, :no_adapter_needed}

      :error ->
        if Code.ensure_loaded?(adapter) and function_exported?(adapter, :deliver, 2) do
          {:ok, adapter}
        else
          {:error,
           "#{inspect(adapter)} is not a valid adapter - must be one of :pid, :bus, :named, :pubsub, :logger, :console, :noop, :http, :webhook or a module implementing deliver/2"}
        end
    end
  end
end
