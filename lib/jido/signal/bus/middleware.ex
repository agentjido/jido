defmodule Jido.Signal.Bus.Middleware do
  @moduledoc """
  Behavior for signal bus middleware modules.

  Middleware modules can intercept and transform signals at various points in the bus lifecycle:
  - Before signals are published to the bus
  - After signals are published but before they are dispatched to subscribers
  - Before signals are dispatched to individual subscribers
  - After signals are dispatched to subscribers

  Middleware modules implement callbacks that receive the signal and context, and can:
  - Transform the signal
  - Add metadata
  - Log signal activity
  - Filter signals
  - Perform side effects

  ## Example

  See `Jido.Signal.Bus.Middleware.Logger` for a complete implementation example.
  """

  alias Jido.Signal
  alias Jido.Signal.Bus.Subscriber

  @type middleware_state :: term()
  @type context :: %{
          bus_name: atom(),
          timestamp: DateTime.t(),
          metadata: map()
        }
  @type dispatch_result :: :ok | {:error, term()}

  @doc """
  Initialize the middleware with the given options.

  This callback is called when the middleware is added to the bus.
  It should return {:ok, state} where state will be passed to all other callbacks.
  """
  @callback init(opts :: keyword()) :: {:ok, middleware_state()} | {:error, term()}

  @doc """
  Called before signals are published to the bus.

  Can transform signals or prevent publication by returning :halt.

  ## Parameters
  - signals: List of signals about to be published
  - context: Context information about the operation
  - state: Current middleware state

  ## Returns
  - {:cont, signals, new_state} - Continue with potentially modified signals
  - {:halt, reason, state} - Stop processing and return error
  """
  @callback before_publish(
              signals :: [Signal.t()],
              context :: context(),
              state :: middleware_state()
            ) ::
              {:cont, [Signal.t()], middleware_state()}
              | {:halt, term(), middleware_state()}

  @doc """
  Called after signals are successfully published to the bus.

  Cannot modify signals but can perform side effects or update middleware state.

  ## Parameters
  - signals: List of signals that were published
  - context: Context information about the operation
  - state: Current middleware state

  ## Returns
  - {:cont, signals, new_state} - Continue processing
  """
  @callback after_publish(
              signals :: [Signal.t()],
              context :: context(),
              state :: middleware_state()
            ) ::
              {:cont, [Signal.t()], middleware_state()}

  @doc """
  Called before a signal is dispatched to a specific subscriber.

  Can transform the signal or prevent dispatch to this subscriber.

  ## Parameters
  - signal: The signal about to be dispatched
  - subscriber: The subscriber that will receive the signal
  - context: Context information about the operation
  - state: Current middleware state

  ## Returns
  - {:cont, signal, new_state} - Continue with potentially modified signal
  - {:skip, state} - Skip this subscriber
  - {:halt, reason, state} - Stop all dispatch for this signal
  """
  @callback before_dispatch(
              signal :: Signal.t(),
              subscriber :: Subscriber.t(),
              context :: context(),
              state :: middleware_state()
            ) ::
              {:cont, Signal.t(), middleware_state()}
              | {:skip, middleware_state()}
              | {:halt, term(), middleware_state()}

  @doc """
  Called after a signal is dispatched to a subscriber.

  Cannot modify the signal but can react to dispatch results.

  ## Parameters
  - signal: The signal that was dispatched
  - subscriber: The subscriber that received the signal
  - result: The result of the dispatch operation
  - context: Context information about the operation
  - state: Current middleware state

  ## Returns
  - {:cont, new_state} - Continue processing
  """
  @callback after_dispatch(
              signal :: Signal.t(),
              subscriber :: Subscriber.t(),
              result :: dispatch_result(),
              context :: context(),
              state :: middleware_state()
            ) ::
              {:cont, middleware_state()}

  @optional_callbacks [
    before_publish: 3,
    after_publish: 3,
    before_dispatch: 4,
    after_dispatch: 5
  ]

  @doc """
  Default implementation that can be used by middleware modules.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Jido.Signal.Bus.Middleware

      @impl true
      def init(_opts), do: {:ok, %{}}

      @impl true
      def before_publish(signals, _context, state), do: {:cont, signals, state}

      @impl true
      def after_publish(signals, _context, state), do: {:cont, signals, state}

      @impl true
      def before_dispatch(signal, _subscriber, _context, state), do: {:cont, signal, state}

      @impl true
      def after_dispatch(_signal, _subscriber, _result, _context, state), do: {:cont, state}

      defoverridable init: 1,
                     before_publish: 3,
                     after_publish: 3,
                     before_dispatch: 4,
                     after_dispatch: 5
    end
  end
end
