defmodule Jido.Flow.Identity.Hash do
  @moduledoc false

  import Bitwise

  @type t :: %{
          algorithm: :sha256,
          digest: String.t(),
          uuid: String.t()
        }

  @doc false
  @spec digest(term()) :: String.t()
  def digest(data) do
    data
    |> raw_digest()
    |> Base.encode16(case: :lower)
  end

  @doc false
  @spec identity(term()) :: t()
  def identity(data) do
    raw_digest = raw_digest(data)

    %{
      algorithm: :sha256,
      digest: Base.encode16(raw_digest, case: :lower),
      uuid: uuid_v8(raw_digest)
    }
  end

  defp raw_digest(data), do: hash_term({:jido_flow_identity, data})

  defp hash_term(term) do
    case :erlang.term_to_iovec(term, [:deterministic]) do
      [bytes] ->
        :crypto.hash(:sha256, bytes)

      segments ->
        segments
        |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
        |> :crypto.hash_final()
    end
  end

  defp uuid_v8(
         <<time_low::32, time_mid::16, version_bits::16, variant_bits::16, node::48, _::binary>>
       ) do
    version_bits = bor(band(version_bits, 0x0FFF), 0x8000)
    variant_bits = bor(band(variant_bits, 0x3FFF), 0x8000)

    encoded =
      Base.encode16(
        <<time_low::32, time_mid::16, version_bits::16, variant_bits::16, node::48>>,
        case: :lower
      )

    <<first::binary-size(8), second::binary-size(4), third::binary-size(4),
      fourth::binary-size(4), fifth::binary-size(12)>> = encoded

    <<first::binary, "-", second::binary, "-", third::binary, "-", fourth::binary, "-",
      fifth::binary>>
  end
end
