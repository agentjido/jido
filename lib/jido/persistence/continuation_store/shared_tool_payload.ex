defmodule Jido.Persistence.ContinuationStore.SharedToolPayload do
  @moduledoc false

  alias Jido.Persistence.{Config, Store}
  alias Jido.Persistence.ContinuationStore.ToolPayload

  @prefix "jido:tool-payload:v1:"

  def candidates(context) do
    context
    |> sessions()
    |> Enum.reduce(%{}, &session_payloads/2)
  end

  def available(%Config{} = config, id, candidates, catalogue) do
    Enum.reduce_while(candidates, {:ok, %{}}, fn {digest, bytes}, {:ok, found} ->
      if ToolPayload.known?(catalogue, bytes) do
        {:cont, {:ok, found}}
      else
        case read(config, id, digest) do
          {:ok, ^bytes} -> {:cont, {:ok, Map.put(found, digest, bytes)}}
          {:error, :not_found} -> {:cont, {:ok, found}}
          {:ok, _wrong} -> {:halt, {:error, :invalid_execution_checkpoint}}
          {:error, _reason} = error -> {:halt, error}
        end
      end
    end)
  end

  def save(config, id, payloads) do
    Enum.reduce_while(payloads, :ok, fn {digest, bytes}, :ok ->
      case save_one(config, id, digest, bytes) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

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

  defp save_one(config, id, digest, bytes) do
    case Store.compare_and_swap(config.store, key(id, digest), :not_found, bytes) do
      :ok ->
        :ok

      {:error, :conflict} ->
        case read(config, id, digest) do
          {:ok, ^bytes} -> :ok
          _wrong -> {:error, :invalid_execution_checkpoint}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp key({:jido_execution, namespace, partition, agent_id, _turn_id}, digest) do
    scope = Base.url_encode64(:erlang.term_to_binary({namespace, partition, agent_id}), padding: false)
    @prefix <> scope <> ":" <> Base.url_encode64(digest, padding: false)
  end

  defp sessions(%{agent_state: %{session: session}} = context), do: [session, Map.get(context, :jido_ai_session)]
  defp sessions(%{jido_ai_session: session}), do: [session]
  defp sessions(_context), do: []

  defp session_payloads(nil, payloads), do: payloads

  defp session_payloads(value, payloads) do
    case Jido.Session.decode(value) do
      {:ok, session} -> Enum.reduce(session.thread.entries, payloads, &entry_payloads/2)
      {:error, _reason} -> payloads
    end
  end

  defp entry_payloads(%{kind: :ai_message, payload: %{"role" => "tool"} = tool}, payloads),
    do: ToolPayload.payloads(tool, payloads)

  defp entry_payloads(%{kind: :ai_tool_attempt, payload: tool}, payloads),
    do: ToolPayload.payloads(tool, payloads)

  defp entry_payloads(_entry, payloads), do: payloads
end
