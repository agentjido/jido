defmodule Jido.Signal.DispatchHelpers do
  @moduledoc """
  Convenience functions for working with dispatch configuration on Signals.

  These functions provide a simplified API for attaching, retrieving, and checking
  dispatch configuration on signals without needing to work with the extension
  system directly.

  ## Examples

      alias Jido.Signal
      alias Jido.Signal.DispatchHelpers

      {:ok, signal} = Signal.new("user.created", %{user_id: "123"}, source: "/users")
      {:ok, signal} = DispatchHelpers.put_dispatch(signal, {:logger, level: :info})

      dispatch = DispatchHelpers.get_dispatch(signal)
      # => {:logger, [level: :info]}

      DispatchHelpers.has_dispatch?(signal)
      # => true

  """

  alias Jido.Signal

  @dispatch_extension "dispatch"

  @doc """
  Returns the extension key used for dispatch configuration.
  """
  @spec dispatch_extension_key() :: String.t()
  def dispatch_extension_key, do: @dispatch_extension

  @doc """
  Attaches dispatch configuration to a signal.

  ## Examples

      {:ok, signal} = Signal.new(%{type: "user.created", ...})
      {:ok, signal} = DispatchHelpers.put_dispatch(signal, {:logger, level: :info})

  """
  @spec put_dispatch(Signal.t(), term()) :: {:ok, Signal.t()} | {:error, String.t()}
  def put_dispatch(%Signal{} = signal, config) do
    Signal.put_extension(signal, @dispatch_extension, config)
  end

  @doc """
  Gets the dispatch configuration from a signal.

  Returns `nil` or the provided default if no dispatch is configured.

  ## Examples

      dispatch = DispatchHelpers.get_dispatch(signal)
      dispatch = DispatchHelpers.get_dispatch(signal, {:noop, []})

  """
  @spec get_dispatch(Signal.t() | nil, term()) :: term()
  def get_dispatch(signal, default \\ nil)

  def get_dispatch(nil, default), do: default

  def get_dispatch(%Signal{} = signal, default) do
    case Signal.get_extension(signal, @dispatch_extension) do
      nil -> default
      value -> value
    end
  end

  @doc """
  Returns true if the signal has dispatch configuration attached.
  """
  @spec has_dispatch?(Signal.t()) :: boolean()
  def has_dispatch?(%Signal{} = signal) do
    Signal.get_extension(signal, @dispatch_extension) != nil
  end
end
