defmodule Jido.AgentServer.CheckpointStore do
  @moduledoc false
  alias Jido.Persistence.Store

  @prefix "jido:execution:v1:"

  def identity(init, id) do
    {:jido_execution, Jido.namespace(init.jido), init.partition, init.agent_id, id}
  end

  def register(jido, id, config, owner \\ self()),
    do: Jido.RuntimeStore.put(jido, __MODULE__, id, {owner, config})

  def unregister(jido, id), do: Jido.RuntimeStore.delete_owned(jido, __MODULE__, id, self())

  def create(jido, id) do
    with {:ok, config} <- config(jido, id) do
      case read(config, id) do
        {:ok, _record} -> :ok
        {:error, :not_found} -> write(config, id, :not_found, %{fmt: 1, log: nil})
        error -> error
      end
    end
  end

  def save({:jido_execution, _, _, _, _} = id, log, jido) do
    with {:ok, config} <- config(jido, id),
         {:ok, bytes, condition} <- Store.read(config, key(id)),
         {:ok, _record} <- decode(bytes) do
      write(config, id, condition, %{fmt: 1, log: log})
    end
  end

  # Ordinary Action Turns do not save execution graphs.
  def save(_id, _log, _jido), do: :ok

  def load({:jido_execution, _, _, _, _} = id, jido) do
    with {:ok, config} <- config(jido, id),
         {:ok, %{log: log}} when is_list(log) <- read(config, id) do
      {:ok, log}
    else
      {:ok, %{log: nil}} -> {:error, :not_found}
      error -> error
    end
  end

  def load(_id, _jido), do: {:error, :not_found}

  defp config(jido, id) when is_atom(jido) and not is_nil(jido) do
    case Jido.RuntimeStore.fetch(jido, __MODULE__, id) do
      {:ok, {owner, config}} ->
        if Process.alive?(owner), do: {:ok, config}, else: {:error, :execution_owner_lost}

      _ ->
        {:error, :execution_store_unavailable}
    end
  end

  defp config(_jido, _id), do: {:error, :execution_store_unavailable}

  defp read(config, id) do
    with {:ok, bytes, _condition} <- Store.read(config, key(id)) do
      decode(bytes)
    end
  end

  defp decode(bytes) do
    # Native Runic logs contain code references and domain atoms. Read only
    # trusted checkpoints written by this runtime, never ingress payloads.
    # :safe cannot restore event atoms which a fresh BEAM has not loaded.
    case :erlang.binary_to_term(bytes) do
      %{fmt: 1, log: log} = record
      when map_size(record) == 2 and (is_list(log) or is_nil(log)) ->
        {:ok, record}

      _ ->
        {:error, :invalid_execution_checkpoint}
    end
  rescue
    ArgumentError -> {:error, :invalid_execution_checkpoint}
  end

  defp write(config, id, condition, record),
    do: Store.compare_and_swap(config, key(id), condition, :erlang.term_to_binary(record))

  defp key(id), do: @prefix <> Base.url_encode64(:erlang.term_to_binary(id), padding: false)
end
