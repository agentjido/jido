defmodule Jido.Test.Persistence.FaultAdapter do
  @moduledoc false

  use Agent

  @behaviour Jido.Persistence.Store

  alias Jido.Persistence.Store

  def start_link(_opts), do: Agent.start_link(fn -> :pass end)

  def configure(control, mode), do: Agent.update(control, fn _current -> mode end)

  @impl true
  def validate_options(opts) do
    with true <- Keyword.keyword?(opts),
         true <- Keyword.keys(opts) -- [:delegate, :control] == [],
         true <- Keyword.keys(opts) == Enum.uniq(Keyword.keys(opts)),
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
    control = Keyword.fetch!(opts, :control)

    mode =
      Agent.get_and_update(control, fn
        {:read_error, prefix, _reason} = mode ->
          if String.starts_with?(key, prefix), do: {mode, :pass}, else: {:pass, mode}

        mode ->
          {:pass, mode}
      end)

    case mode do
      {:read_error, _prefix, reason} ->
        {:error, reason}

      :pass ->
        with {:ok, bytes, condition} <- Store.read(Keyword.fetch!(opts, :delegate), key) do
          case condition do
            {:token, token} -> {:ok, bytes, token}
            ^bytes -> {:ok, bytes}
          end
        end
    end
  end

  @impl true
  def compare_and_swap(key, expected, value, opts) do
    mode =
      Agent.get_and_update(Keyword.fetch!(opts, :control), fn
        {:write_error, prefix, _reason} = mode ->
          if String.starts_with?(key, prefix), do: {mode, :pass}, else: {:pass, mode}

        mode ->
          {mode, :pass}
      end)

    case mode do
      :pass -> write(key, expected, value, opts)
      {:rejected, reason} -> {:error, {:rejected, reason}}
      {:lost_reply, reason} -> lose_reply(key, expected, value, reason, opts)
      {:write_error, _prefix, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(key, opts), do: Store.delete(Keyword.fetch!(opts, :delegate), key)

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
