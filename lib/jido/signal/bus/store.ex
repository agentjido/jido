defmodule Jido.Signal.Bus.Store do
  @moduledoc """
  Defines the small storage boundary that the Signal Bus owns.

  A store keeps ordered Bus records and durable subscription definitions. A
  durable definition contains its stable ID, path, cursor, creation time, and
  `format_version: 1`. Records also use `format_version: 1`.

  `list_subscriptions/1` must return definitions in creation order. `append/2`
  must accept all records or none. The Bus stores the returned state and passes
  it to the next callback.

  Return `{:error, {:outcome_unknown, reason}}` if a write can have committed
  without an acknowledgment. The Bus also treats `{:error, :timeout}` as
  uncertain. Reads with the last acknowledged adapter state must report the
  authoritative records and subscription cursors before the Bus can write
  again. Other error returns mean the write did not commit.

  Only `Jido.Signal.Bus.Store.Memory` is included. A custom adapter can keep an
  external resource in its state when records must survive a Bus restart.
  A custom adapter must set a finite timeout on each external operation. Store
  callbacks run in the Bus process and must not wait without a bound.
  """

  @type state :: term()
  @type stored_record :: %{required(String.t()) => term()}
  @type subscription :: %{required(String.t()) => term()}
  @type subscription_id :: String.t()

  @callback init(keyword()) :: {:ok, state()} | {:error, term()}
  @callback append([stored_record()], state()) :: {:ok, state()} | {:error, term()}
  @doc """
  Reads records after an exclusive `:after_cursor`.

  The optional `:path` filters Signal types. The optional `:limit` is a positive
  integer or `:infinity`.
  """
  @callback read(keyword(), state()) :: {:ok, [stored_record()]} | {:error, term()}
  @callback latest_cursor(state()) :: {:ok, non_neg_integer()} | {:error, term()}
  @callback list_subscriptions(state()) :: {:ok, [subscription()]} | {:error, term()}
  @callback put_subscription(subscription(), state()) :: {:ok, state()} | {:error, term()}
  @callback delete_subscription(subscription_id(), state()) :: {:ok, state()} | {:error, term()}

  @doc false
  @spec init_adapter(module(), keyword()) :: {:ok, state()} | {:error, term()}
  def init_adapter(module, opts) do
    case safe_apply(module, :init, [opts]) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:error, {:store_init_failed, reason}}
      other -> {:error, {:store_init_failed, {:invalid_return, other}}}
    end
  end

  @doc false
  @spec read(module(), state(), atom(), [term()]) :: {:ok, term()} | {:error, term()}
  def read(module, state, callback, args) do
    case safe_apply(module, callback, args ++ [state]) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, {:store_error, callback, reason}}
      other -> {:error, {:store_error, callback, {:invalid_return, other}}}
    end
  end

  @doc false
  @spec read(map(), atom(), [term()]) :: {:ok, term()} | {:error, term()}
  def read(bus_state, callback, args) do
    read(bus_state.store_module, bus_state.store_state, callback, args)
  end

  @doc false
  @spec write(map(), atom(), [term()]) :: {:ok, map()} | {:error, term()}
  def write(bus_state, callback, args) do
    case safe_apply(
           bus_state.store_module,
           callback,
           args ++ [bus_state.store_state]
         ) do
      {:ok, store_state} -> {:ok, %{bus_state | store_state: store_state}}
      {:error, reason} -> {:error, {:store_error, callback, reason}}
      other -> {:error, {:store_error, callback, {:invalid_return, other}}}
    end
  end

  @doc false
  def unknown_outcome?({:store_error, _callback, {:outcome_unknown, _reason}}), do: true
  def unknown_outcome?({:store_error, _callback, :timeout}), do: true
  def unknown_outcome?({:store_error, _callback, {:exit, {:timeout, _call}}}), do: true
  def unknown_outcome?(_reason), do: false

  defp safe_apply(module, callback, args) do
    apply(module, callback, args)
  rescue
    error -> {:error, {:exception, error}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
