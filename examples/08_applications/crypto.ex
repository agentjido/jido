defmodule Jido.Examples.Applications.Crypto do
  @moduledoc false

  alias Jido.Signal

  @public_key_context "jidopubkey"
  @signature_context "jidosignature"
  @nonce_context "jidononce"

  def peer_key_pair, do: key_pair(1)
  def agent_key_pair, do: key_pair(2)
  def secure_key, do: :binary.copy(<<3>>, 32)

  def sign(%Signal{} = signal, private_key, public_key, nonce \\ random_nonce()) do
    with {:ok, signal} <- Signal.put_context(signal, @public_key_context, public_key),
         {:ok, signal} <- Signal.put_context(signal, @nonce_context, nonce),
         signature =
           :crypto.sign(:eddsa, :none, identity_payload(signal), [private_key, :ed25519]),
         {:ok, signal} <- Signal.put_context(signal, @signature_context, signature) do
      {:ok, signal}
    end
  end

  def verify(%Signal{} = signal, trusted_public_key) do
    public_key = Signal.get_context(signal, @public_key_context)
    signature = Signal.get_context(signal, @signature_context)
    nonce = Signal.get_context(signal, @nonce_context)

    cond do
      public_key != trusted_public_key ->
        {:error, :untrusted_public_key}

      not is_binary(signature) ->
        {:error, :missing_signature}

      not is_binary(nonce) ->
        {:error, :missing_identity_nonce}

      :crypto.verify(:eddsa, :none, identity_payload(signal), signature, [public_key, :ed25519]) ->
        {:ok, nonce}

      true ->
        {:error, :invalid_signature}
    end
  end

  def identity_public_key(%Signal{} = signal) do
    Signal.get_context(signal, @public_key_context)
  end

  def encrypt(%Signal{} = signal, key, plaintext) do
    nonce = :crypto.strong_rand_bytes(12)
    encoded = :erlang.term_to_binary(plaintext, [:deterministic])

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, encoded, secure_aad(signal), true)

    %{
      "nonce" => nonce,
      "ciphertext" => ciphertext,
      "tag" => tag
    }
  end

  def decrypt(%Signal{} = signal, key, envelope) when is_map(envelope) do
    with {:ok, nonce} <- fetch_binary(envelope, "nonce"),
         {:ok, ciphertext} <- fetch_binary(envelope, "ciphertext"),
         {:ok, tag} <- fetch_binary(envelope, "tag"),
         plaintext when is_binary(plaintext) <-
           :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             key,
             nonce,
             ciphertext,
             secure_aad(signal),
             tag,
             false
           ) do
      {:ok, :erlang.binary_to_term(plaintext, [:safe])}
    else
      :error -> {:error, :decryption_failed}
      {:error, _reason} = error -> error
    end
  rescue
    _error -> {:error, :decryption_failed}
  end

  def decrypt(%Signal{}, _key, _envelope), do: {:error, :invalid_secure_envelope}

  def random_nonce, do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

  defp key_pair(byte) do
    :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<byte>>, 32))
  end

  defp identity_payload(%Signal{} = signal) do
    extensions = Map.delete(signal.extensions, @signature_context)

    :erlang.term_to_binary(
      {
        signal.specversion,
        signal.id,
        signal.source,
        signal.type,
        signal.subject,
        signal.time,
        signal.datacontenttype,
        signal.dataschema,
        signal.data,
        extensions
      },
      [:deterministic]
    )
  end

  defp secure_aad(%Signal{} = signal) do
    :erlang.term_to_binary({signal.id, signal.source, signal.type}, [:deterministic])
  end

  defp fetch_binary(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      _other -> {:error, :invalid_secure_envelope}
    end
  end
end
