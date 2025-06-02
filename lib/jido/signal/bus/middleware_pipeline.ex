defmodule Jido.Signal.Bus.MiddlewarePipeline do
  @moduledoc """
  Handles execution of middleware chains for signal bus operations.

  This module provides functions to execute middleware callbacks in sequence,
  allowing each middleware to transform signals or control the flow of execution.
  """

  alias Jido.Signal
  alias Jido.Signal.Bus.Middleware
  alias Jido.Signal.Bus.Subscriber

  @type middleware_config :: {module(), term()}
  @type context :: Middleware.context()

  @doc """
  Executes the before_publish middleware chain.

  Stops execution if any middleware returns :halt.
  """
  @spec before_publish([middleware_config()], [Signal.t()], context()) ::
          {:ok, [Signal.t()]} | {:error, term()}
  def before_publish(middleware_configs, signals, context) do
    middleware_configs
    |> Enum.reduce_while({:ok, signals}, fn {module, state}, {:ok, current_signals} ->
      if function_exported?(module, :before_publish, 3) do
        case module.before_publish(current_signals, context, state) do
          {:cont, new_signals, _new_state} ->
            {:cont, {:ok, new_signals}}

          {:halt, reason, _state} ->
            {:halt, {:error, reason}}
        end
      else
        {:cont, {:ok, current_signals}}
      end
    end)
  end

  @doc """
  Executes the after_publish middleware chain.

  This is called for side effects only - signals cannot be modified.
  """
  @spec after_publish([middleware_config()], [Signal.t()], context()) :: :ok
  def after_publish(middleware_configs, signals, context) do
    Enum.each(middleware_configs, fn {module, state} ->
      if function_exported?(module, :after_publish, 3) do
        module.after_publish(signals, context, state)
      end
    end)
  end

  @doc """
  Executes the before_dispatch middleware chain for a single signal and subscriber.

  Returns the potentially modified signal, or indicates if dispatch should be skipped/halted.
  """
  @spec before_dispatch([middleware_config()], Signal.t(), Subscriber.t(), context()) ::
          {:ok, Signal.t()} | :skip | {:error, term()}
  def before_dispatch(middleware_configs, signal, subscriber, context) do
    middleware_configs
    |> Enum.reduce_while({:ok, signal}, fn {module, state}, {:ok, current_signal} ->
      if function_exported?(module, :before_dispatch, 4) do
        case module.before_dispatch(current_signal, subscriber, context, state) do
          {:cont, new_signal, _new_state} ->
            {:cont, {:ok, new_signal}}

          {:skip, _state} ->
            {:halt, :skip}

          {:halt, reason, _state} ->
            {:halt, {:error, reason}}
        end
      else
        {:cont, {:ok, current_signal}}
      end
    end)
  end

  @doc """
  Executes the after_dispatch middleware chain.

  This is called for side effects only after a signal has been dispatched.
  """
  @spec after_dispatch(
          [middleware_config()],
          Signal.t(),
          Subscriber.t(),
          Middleware.dispatch_result(),
          context()
        ) :: :ok
  def after_dispatch(middleware_configs, signal, subscriber, result, context) do
    Enum.each(middleware_configs, fn {module, state} ->
      if function_exported?(module, :after_dispatch, 5) do
        module.after_dispatch(signal, subscriber, result, context, state)
      end
    end)
  end

  @doc """
  Initializes a list of middleware modules with their options.

  Returns a list of {module, state} tuples that can be used in the pipeline.
  """
  @spec init_middleware([{module(), keyword()}]) ::
          {:ok, [middleware_config()]} | {:error, term()}
  def init_middleware(middleware_specs) do
    middleware_specs
    |> Enum.reduce_while({:ok, []}, fn {module, opts}, {:ok, acc} ->
      case module.init(opts) do
        {:ok, state} ->
          {:cont, {:ok, [{module, state} | acc]}}

        {:error, reason} ->
          {:halt, {:error, {:middleware_init_failed, module, reason}}}
      end
    end)
    |> case do
      {:ok, configs} -> {:ok, Enum.reverse(configs)}
      error -> error
    end
  end
end
