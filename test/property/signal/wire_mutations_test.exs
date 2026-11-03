Code.require_file("support/fuzz.exs", __DIR__)

defmodule JidoTest.Property.Signal.WireMutationsTest do
  use ExUnit.Case, async: true
  import StreamData
  alias Jido.Signal.Codec
  alias JidoTest.Property.Signal.Fuzz

  @mutations ~w(missing-id missing-version version both base64 extension key legacy type)
  for {suite, runs, bound} <- [{:property, 40, 32}, {:fuzz, 500, 512}] do
    @tag [
      {suite, true},
      max_runs: runs,
      max_run_time: if(suite == :fuzz, do: 300_000, else: 10_000),
      timeout: if(suite == :fuzz, do: 900_000, else: 90_000)
    ]
    @tag contracts: ["WIRE-002"]
    @tag contract_cases: [
           "WIRE-002/known-invalid",
           "WIRE-002/atomic-batch",
           "WIRE-002/exact-size",
           "WIRE-002/compressed-etf",
           "WIRE-002/malformed-input"
         ]
    test "#{suite}: invalid wire data and byte limits", context do
      generator =
        fixed_map(%{
          "mutation" => member_of(@mutations),
          "text" => string(:alphanumeric, max_length: unquote(bound))
        })

      examples = for mutation <- @mutations, do: %{"mutation" => mutation, "text" => "boundary"}

      Fuzz.check(
        "wire_mutations",
        generator,
        Map.to_list(context) ++ [examples: examples],
        &check/1
      )
    end
  end

  defp check(%{"mutation" => mutation, "text" => text}) do
    map = %{
      "specversion" => "1.0",
      "id" => "wire",
      "source" => "/property",
      "type" => "event.a",
      "data" => text
    }

    bad = mutate(map, mutation)
    assert {:error, _} = Codec.from_map(bad)
    assert {:ok, signal} = Codec.from_map(map)

    for format <- [:json, :erlang_term] do
      assert {:error, _} = Codec.deserialize(encode([map, bad, map], format), format: format)
      assert {:ok, binary} = Codec.serialize(signal, format: format)
      size = byte_size(binary)
      assert {:ok, ^binary} = Codec.serialize(signal, format: format, max_payload_bytes: size)
      assert {:ok, ^signal} = Codec.deserialize(binary, format: format, max_payload_bytes: size)

      assert {:error, {:payload_too_large, ^size, below}} =
               Codec.serialize(signal, format: format, max_payload_bytes: size - 1)

      assert below == size - 1

      assert {:error, {:payload_too_large, ^size, ^below}} =
               Codec.deserialize(binary, format: format, max_payload_bytes: below)

      assert {:error, _} =
               Codec.deserialize(encode([map | :invalid_tail], :erlang_term),
                 format: :erlang_term
               )
    end

    compressed =
      :erlang.term_to_binary(Map.put(map, "data", String.duplicate("a", 10_000)), [:compressed])

    assert <<131, 80, _::binary>> = compressed

    assert {:error, {:erlang_term_decode_failed, _}} =
             Codec.deserialize(compressed, format: :erlang_term)

    assert {:error, {:json_decode_failed, _}} = Codec.deserialize("{" <> text)

    assert {:error, {:erlang_term_decode_failed, _}} =
             Codec.deserialize(<<131, 255>>, format: :erlang_term)

    assert {:error, _} = Codec.serialize([signal | :tail])
    assert {:error, {:unsupported_format, :invalid}} = Codec.serialize(signal, format: :invalid)
    assert {:error, {:invalid_options, _}} = Codec.deserialize("{}", [:bad])

    assert {:error, {:invalid_max_payload_bytes, -1}} =
             Codec.serialize(signal, max_payload_bytes: -1)

    ["mutation-#{mutation}", "size-boundary"]
  end

  defp mutate(map, "missing-id"), do: Map.delete(map, "id")
  defp mutate(map, "missing-version"), do: Map.delete(map, "specversion")
  defp mutate(map, "version"), do: Map.put(map, "specversion", "0.3")
  defp mutate(map, "both"), do: Map.put(map, "data_base64", "YQ==")
  defp mutate(map, "base64"), do: map |> Map.delete("data") |> Map.put("data_base64", "!")
  defp mutate(map, "extension"), do: Map.put(map, "ext", [1])
  defp mutate(map, "key"), do: Map.put(map, "Upper", 1)
  defp mutate(map, "legacy"), do: Map.put(map, "jido_schema_version", 99)
  defp mutate(map, "type"), do: Map.put(map, "type", "bad\n")
  defp encode(map, :json), do: Jason.encode!(map)
  defp encode(map, :erlang_term), do: :erlang.term_to_binary(map)
end
