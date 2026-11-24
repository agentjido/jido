defmodule Jido.Persistence.ContinuationStore.ToolReceipt do
  @moduledoc false

  alias Jido.Persistence.{Config, Store}
  alias Jido.Persistence.ContinuationStore.{SharedToolPayload, ToolPayload}

  def build(profile, signature, {%{normalized: outcome}, _effects} = result) do
    with :ok <- validate_result(result),
         {:ok, encoded} <- Config.encode(profile, result) do
      payloads = ToolPayload.payloads(outcome)
      local = ToolPayload.add(ToolPayload.new(), :local, payloads)
      receipt = {:jido_tool_result, 1, signature, payloads, ToolPayload.pack(encoded, local)}
      {:ok, receipt, payloads}
    end
  end

  def read(profile, key, opts) do
    with {:ok, bytes, _condition} <- Store.read(profile.store, key) do
      with {:ok, receipt} <- Config.decode(profile, bytes, opts),
           true <- valid_record?(receipt) do
        {:ok, receipt}
      else
        _invalid -> {:error, :invalid_execution_checkpoint}
      end
    end
  end

  def payloads(_profile, _id, {:jido_tool_result, 1, _signature, payloads, _body}), do: {:ok, payloads}

  def payloads(profile, id, {:jido_tool_result, 2, _signature, digests, _body}),
    do: SharedToolPayload.fetch(profile, id, digests)

  def add_payloads({:jido_tool_result, 1, _, _, _}, catalogue, slot, payloads),
    do: ToolPayload.add(catalogue, slot, payloads)

  def add_payloads({:jido_tool_result, 2, _, _, _}, catalogue, _slot, payloads),
    do: ToolPayload.add_shared(catalogue, payloads)

  def result(profile, id, {:jido_tool_result, _version, signature, _refs, body} = receipt, signature) do
    with {:ok, payloads} <- payloads(profile, id, receipt),
         {:ok, bytes} <- ToolPayload.unpack(body, &load_payloads(&1, payloads)),
         {:ok, {%{normalized: normalized}, effects} = result} when is_map(normalized) and is_list(effects) <-
           Config.decode(profile, bytes, trusted: true),
         :ok <- validate_result(result) do
      {:ok, result, receipt, payloads}
    else
      _invalid -> {:error, :invalid_execution_checkpoint}
    end
  end

  def result(_profile, _id, _receipt, _signature), do: {:error, :tool_call_changed_on_replay}

  defp load_payloads(:local, payloads), do: {:ok, payloads}
  defp load_payloads({:shared, digest}, payloads), do: {:ok, Map.take(payloads, [digest])}
  defp load_payloads(_other, _payloads), do: {:error, :invalid_execution_checkpoint}

  defp validate_result(result) do
    if Jido.Codec.Term.valid?(result),
      do: :ok,
      else: {:error, :non_portable_flow_output}
  end

  def valid_record?({:jido_tool_result, 1, signature, payloads, _body}) when is_map(payloads),
    do: digest?(signature) and Enum.all?(payloads, &valid_payload?/1)

  def valid_record?({:jido_tool_result, 2, signature, digests, _body}) when is_list(digests),
    do: digest?(signature) and not List.improper?(digests) and Enum.all?(digests, &digest?/1)

  def valid_record?(_receipt), do: false

  defp digest?(digest), do: is_binary(digest) and byte_size(digest) == 32
  defp valid_payload?({digest, bytes}), do: is_binary(bytes) and ToolPayload.digest(bytes) == digest
end
