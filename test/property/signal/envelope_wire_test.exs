Code.require_file("../support/fuzz.exs", __DIR__)

defmodule JidoTest.Property.Signal.EnvelopeWireTest do
  use ExUnit.Case, async: true
  import StreamData
  alias Jido.Id
  alias Jido.Signal
  alias Jido.Signal.Codec
  alias JidoTest.Property.Fuzz

  defmodule CountSignal do
    use Jido.Signal,
      type: "domain.count",
      default_source: "/counts",
      schema: Zoi.object(%{count: Zoi.integer()})
  end

  @modes ~w(absent null false true json text base64 opaque)
  @times [
    nil,
    "2026-09-29T12:00:00Z",
    "2026-09-29t12:00:00.1234567z",
    "2017-01-01T00:59:60+01:00",
    "2026-09-29 12:00:00+00:00"
  ]

  for {suite, runs, bound} <- [{:property, 40, 6}, {:fuzz, 500, 20}] do
    @tag [
      {suite, true},
      fuzz_id: "envelope_wire",
      max_runs: runs,
      max_run_time: if(suite == :fuzz, do: 300_000, else: 10_000),
      timeout: if(suite == :fuzz, do: 900_000, else: 90_000)
    ]
    test "#{suite}: canonical envelope and flat context", context do
      generator =
        fixed_map(%{
          "mode" => member_of(@modes),
          "n" => integer(-2_147_483_648..2_147_483_647),
          "text" => string(:alphanumeric, max_length: unquote(bound)),
          "time" => member_of(@times)
        })

      examples =
        for mode <- @modes,
            time <- @times,
            do: %{"mode" => mode, "n" => 0, "text" => "é", "time" => time}

      Fuzz.check(
        "envelope_wire",
        generator,
        Map.to_list(context) ++ [examples: examples],
        &check/1
      )
    end
  end

  defp check(%{"mode" => mode, "n" => n, "text" => text, "time" => time}) do
    base = %{
      "specversion" => "1.0",
      "id" => "supplied-#{n}",
      "source" => "/property",
      "type" => "event.a",
      "tenant" => n,
      "label" => text
    }

    base = if time, do: Map.put(base, "time", time), else: base
    {attrs, expected_data, present?} = data(mode, n, text)
    expected = Map.merge(base, attrs)
    constructor = if mode == "opaque", do: Map.put(base, "data", expected_data), else: expected
    assert {:ok, signal} = Signal.new(constructor)
    assert signal.data == expected_data
    assert signal.data_present? == present?
    assert signal.id == base["id"]
    assert Codec.to_map(signal) == expected
    assert {:ok, ^signal} = Codec.from_map(expected)

    for format <- [:json, :erlang_term] do
      assert {:ok, encoded} = Codec.serialize(signal, format: format)

      decoded_map =
        if format == :json,
          do: Jason.decode!(encoded),
          else: :erlang.binary_to_term(encoded, [:safe])

      assert decoded_map == expected
      assert {:ok, ^signal} = Codec.deserialize(encoded, format: format)
      assert {:ok, batch} = Codec.serialize([signal, signal], format: format)
      assert {:ok, [^signal, ^signal]} = Codec.deserialize(batch, format: format)

      assert {:ok, null_context} =
               Codec.deserialize(encode(Map.put(expected, "unset", nil), format), format: format)

      assert Codec.to_map(null_context) == expected
    end

    assert {:ok, generated} = Signal.new(%{"type" => "event.a", "source" => "/property"})
    assert Id.uuid7?(generated.id)
    assert {:ok, custom} = CountSignal.new(%{count: n})
    assert custom.type == "domain.count" and custom.source == "/counts"
    assert custom.data == %{count: n}
    assert {:error, errors} = CountSignal.new(%{count: "invalid"})
    assert is_list(errors)
    core_boundaries(base)
    context_boundaries(signal, n)
    ["data-#{mode}", if(time, do: "explicit-time", else: "absent-time")]
  end

  defp data("absent", _, _), do: {%{}, nil, false}
  defp data("null", _, _), do: {%{"data" => nil}, nil, true}
  defp data("false", _, _), do: {%{"data" => false}, false, true}
  defp data("true", _, _), do: {%{"data" => true}, true, true}

  defp data("json", n, text),
    do:
      {%{"data" => %{"n" => n, "text" => text, "items" => [nil, false]}},
       %{"n" => n, "text" => text, "items" => [nil, false]}, true}

  defp data("text", _, text), do: {%{"data" => text}, text, true}
  defp data("base64", _, text), do: {%{"data_base64" => Base.encode64(text)}, text, true}
  defp data("opaque", _, _), do: {%{"data_base64" => "//4="}, <<255, 254>>, true}

  defp core_boundaries(base) do
    for key <- ["id", "type"], forbidden <- [0, 31, 127, 159, 0xFDD0, 0xFFFF, 0x1FFFE] do
      assert {:error, _} = Signal.new(Map.put(base, key, "x" <> <<forbidden::utf8>>))
    end

    for time <- [
          "2026-02-30T12:00:00Z",
          "2026-09-29T12:00:60Z",
          "2026-09-29T12:00:00,1Z",
          "2026-09-29T12:00:00+24:00"
        ] do
      assert {:error, _} = Signal.new(Map.put(base, "time", time))
    end
  end

  defp context_boundaries(signal, n) do
    for {name, value} <- [
          {"a", n},
          {String.duplicate("a", 20), true},
          {"min", -2_147_483_648},
          {"max", 2_147_483_647}
        ] do
      assert {:ok, updated} = Signal.put_context(signal, name, value)
      assert Signal.get_context(updated, name) == value
      assert Codec.to_map(updated) == Map.put(Codec.to_map(signal), name, value)

      assert Signal.delete_context(updated, name).extensions ==
               Map.delete(updated.extensions, name)
    end

    for {name, value} <- [
          {"", 1},
          {String.duplicate("a", 21), 1},
          {"Upper", 1},
          {"id", 1},
          {"a", nil},
          {"a", []},
          {"a", %{}},
          {"a", 2_147_483_648},
          {"a", -2_147_483_649}
        ] do
      assert {:error, _} = Signal.put_context(signal, name, value)
    end

    assert {:error, _} =
             Signal.new(%{
               type: "event.a",
               source: "/p",
               extensions: %{:tenant => 1, "tenant" => 2}
             })

    unknown = "p#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> :erlang.binary_to_existing_atom(unknown, :utf8) end
    assert {:ok, unknown_signal} = Signal.put_context(signal, unknown, n)
    assert Signal.get_context(unknown_signal, unknown) == n
    assert_raise ArgumentError, fn -> :erlang.binary_to_existing_atom(unknown, :utf8) end

    assert {:ok, opaque} = Signal.put_context(signal, "opaque", <<255>>)
    assert {:ok, binary} = Codec.serialize(opaque, format: :erlang_term)
    assert {:ok, ^opaque} = Codec.deserialize(binary, format: :erlang_term)
    assert {:error, {:json_encode_failed, _}} = Codec.serialize(opaque)
  end

  defp encode(map, :json), do: Jason.encode!(map)
  defp encode(map, :erlang_term), do: :erlang.term_to_binary(map)
end
