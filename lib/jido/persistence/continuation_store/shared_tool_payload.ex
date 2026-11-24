defmodule Jido.Persistence.ContinuationStore.SharedToolPayload do
  @moduledoc false

  alias Jido.Persistence.Store
  alias Jido.Persistence.ContinuationStore.ToolPayload

  @prefix "jido:tool-payload:v1:"

  # Read shared payloads from earlier execution checkpoints. New tool receipts own their bytes.
  def fetch(config, id, digests) do
    Enum.reduce_while(digests, {:ok, %{}}, fn digest, {:ok, found} ->
      case read(config, id, digest) do
        {:ok, bytes} -> {:cont, {:ok, Map.put(found, digest, bytes)}}
        {:error, _reason} -> {:halt, {:error, :invalid_execution_checkpoint}}
      end
    end)
  end

  def read(config, id, digest) do
    with {:ok, bytes, _condition} <- Store.read(config.store, key(id, digest)) do
      if ToolPayload.digest(bytes) == digest,
        do: {:ok, bytes},
        else: {:error, :invalid_execution_checkpoint}
    end
  end

  def inspect_record(@prefix <> suffix, bytes) do
    with [scope, encoded_digest] when scope != "" <- String.split(suffix, ":", parts: 2),
         {:ok, digest} <- Base.url_decode64(encoded_digest, padding: false),
         true <- ToolPayload.digest(bytes) == digest do
      {:ok, {:jido_shared_tool_payload, bytes}}
    else
      _invalid -> {:error, :invalid_execution_checkpoint}
    end
  end

  defp key({:jido_execution, namespace, partition, agent_id, _turn_id}, digest) do
    scope = Base.url_encode64(:erlang.term_to_binary({namespace, partition, agent_id}), padding: false)
    @prefix <> scope <> ":" <> Base.url_encode64(digest, padding: false)
  end
end
