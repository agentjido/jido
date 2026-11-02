defmodule JidoTest.Persistence.FaultAdapter do
  @moduledoc false

  use Agent

  @behaviour Jido.Persistence.Adapter

  alias Jido.Persistence.Store

  def start_link(_opts), do: Agent.start_link(fn -> :pass end)

  def configure(control, mode), do: Agent.update(control, fn _current -> mode end)

  @impl true
  def validate_options(opts) do
    with true <- Keyword.keyword?(opts),
         store when is_tuple(store) <- Keyword.get(opts, :delegate),
         control when is_pid(control) <- Keyword.get(opts, :control),
         {:ok, _store} <- Store.open(store) do
      :ok
    else
      _other -> {:error, :invalid_fault_adapter_options}
    end
  end

  @impl true
  def get(key, opts) do
    with {:ok, bytes, condition} <- Store.read(Keyword.fetch!(opts, :delegate), key) do
      case condition do
        {:token, token} -> {:ok, bytes, token}
        ^bytes -> {:ok, bytes}
      end
    end
  end

  @impl true
  def compare_and_swap(key, expected, value, opts) do
    mode = Agent.get_and_update(Keyword.fetch!(opts, :control), &{&1, :pass})

    case mode do
      :pass -> write(key, expected, value, opts)
      {:rejected, reason} -> {:error, {:rejected, reason}}
      {:lost_reply, reason} -> lose_reply(key, expected, value, reason, opts)
    end
  end

  defp lose_reply(key, expected, value, reason, opts) do
    case write(key, expected, value, opts) do
      :ok -> {:error, {:indeterminate, reason}}
      {:error, _reason} = error -> error
    end
  end

  defp write(key, expected, value, opts) do
    Store.compare_and_swap(Keyword.fetch!(opts, :delegate), key, expected, value)
  end
end
