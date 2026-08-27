defmodule Jido.Agent.SemanticIdentity do
  @moduledoc false

  import Bitwise

  alias Jido.Agent

  @identity_version 1

  @doc false
  @spec for_agent(Agent.t()) :: map()
  def for_agent(%Agent{} = agent) do
    agent
    |> Agent.to_map()
    |> identity()
  end

  @spec identity(map()) :: %{
          version: 1,
          algorithm: :sha256,
          digest: String.t(),
          uuid: String.t()
        }
  defp identity(canonical_identity_map) when is_map(canonical_identity_map) do
    raw_digest =
      {:jido_agent_identity, @identity_version, canonical_identity_map}
      |> hash_term()

    %{
      version: @identity_version,
      algorithm: :sha256,
      digest: Base.encode16(raw_digest, case: :lower),
      uuid: uuid_v8(raw_digest)
    }
  end

  @spec hash_term(term()) :: binary()
  defp hash_term(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
  end

  @spec uuid_v8(binary()) :: String.t()
  defp uuid_v8(
         <<time_low::32, time_mid::16, version_bits::16, variant_bits::16, node::48, _::binary>>
       ) do
    version_bits = bor(band(version_bits, 0x0FFF), 0x8000)
    variant_bits = bor(band(variant_bits, 0x3FFF), 0x8000)

    :io_lib.format(
      ~c"~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
      [time_low, time_mid, version_bits, variant_bits, node]
    )
    |> IO.iodata_to_binary()
  end
end
