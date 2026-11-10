defmodule Jido.Signal.CodecTest do
  use ExUnit.Case, async: false

  alias Jido.Signal
  alias Jido.Signal.Codec, as: SignalCodec

  test "owns the wire API without a Signal compatibility facade" do
    assert function_exported?(SignalCodec, :from_map, 1)
    assert function_exported?(SignalCodec, :to_map, 1)
    assert function_exported?(SignalCodec, :serialize, 2)
    assert function_exported?(SignalCodec, :deserialize, 2)

    refute function_exported?(Signal, :from_map, 1)
    refute function_exported?(Signal, :to_map, 1)
    refute function_exported?(Signal, :serialize, 2)
    refute function_exported?(Signal, :deserialize, 2)
  end

  describe "JSON" do
    test "round-trips one Signal through the canonical map" do
      signal =
        Signal.new!("test.created", %{"count" => 2},
          source: "/test",
          id: "json-1",
          subject: "record/1"
        )

      assert {:ok, json} = Jido.Signal.Codec.serialize(signal)
      assert Jason.decode!(json) == Jido.Signal.Codec.to_map(signal)
      assert {:ok, decoded} = Jido.Signal.Codec.deserialize(json)
      assert decoded == signal
    end

    test "round-trips a list of Signals" do
      signals = [
        Signal.new!(type: "first.created", source: "/test", id: "first"),
        Signal.new!(type: "second.created", source: "/test", id: "second")
      ]

      assert {:ok, json} = Jido.Signal.Codec.serialize(signals)
      assert {:ok, decoded} = Jido.Signal.Codec.deserialize(json)
      assert decoded == signals
    end

    test "returns a tagged error for invalid JSON" do
      assert {:error, {:json_decode_failed, message}} = Jido.Signal.Codec.deserialize("{invalid")
      assert is_binary(message)
    end
  end

  describe "Erlang term format" do
    test "round-trips through the same canonical map" do
      signal = Signal.new!("test.created", %{"count" => 2}, source: "/test")

      assert {:ok, binary} = Jido.Signal.Codec.serialize(signal, format: :erlang_term)
      assert :erlang.binary_to_term(binary, [:safe]) == Jido.Signal.Codec.to_map(signal)
      assert {:ok, decoded} = Jido.Signal.Codec.deserialize(binary, format: :erlang_term)
      assert decoded == signal
    end

    test "returns a tagged error for invalid Erlang term data" do
      assert {:error, {:erlang_term_decode_failed, message}} =
               Jido.Signal.Codec.deserialize(<<1, 2, 3>>, format: :erlang_term)

      assert is_binary(message)
    end

    test "rejects a decoded value that is not a Signal envelope" do
      encoded_function = :erlang.term_to_binary(&System.cmd/3)

      assert {:error, {:invalid_wire_data, message}} =
               Jido.Signal.Codec.deserialize(encoded_function, format: :erlang_term)

      assert message =~ "expected a map"

      valid_wire = Jido.Signal.Codec.to_map(Signal.new!(type: "test.valid", source: "/test"))
      invalid_list = :erlang.term_to_binary([valid_wire, &System.cmd/3])

      assert {:error, {:invalid_wire_data, list_message}} =
               Jido.Signal.Codec.deserialize(invalid_list, format: :erlang_term)

      assert list_message =~ "expected a map"
    end

    test "validates a large batch without recursive stack growth" do
      wire = Jido.Signal.Codec.to_map(Signal.new!(type: "test.large-batch", source: "/test"))
      encoded = :erlang.term_to_binary(List.duplicate(wire, 20_000))

      assert {:ok, signals} =
               Jido.Signal.Codec.deserialize(encoded,
                 format: :erlang_term,
                 max_payload_bytes: byte_size(encoded)
               )

      assert length(signals) == 20_000
    end
  end

  describe "binary and Erlang-only Signal data" do
    test "uses raw bytes in data_base64" do
      data = <<0, 255>>
      signal = Signal.new!("test.binary", data, source: "/test")

      wire = Jido.Signal.Codec.to_map(signal)
      refute Map.has_key?(wire, "data")
      assert Base.decode64!(wire["data_base64"]) == data

      assert {:ok, decoded} = Jido.Signal.Codec.from_map(wire)
      assert decoded.data == data
    end

    test "accepts the CloudEvents raw binary vector" do
      wire = %{
        "specversion" => "1.0",
        "id" => "binary-vector",
        "source" => "/test",
        "type" => "test.binary",
        "data_base64" => "AQID"
      }

      assert {:ok, signal} = Jido.Signal.Codec.from_map(wire)
      assert signal.data == <<1, 2, 3>>
      assert Jido.Signal.Codec.to_map(signal) == wire
    end

    test "keeps Erlang-only values in the trusted term format only" do
      data = %{status: :ready, value: {1, 2}, bytes: <<0, 255>>}
      signal = Signal.new!("test.term", data, source: "/test")

      assert {:error, {:json_encode_failed, _message}} = Jido.Signal.Codec.serialize(signal)
      assert {:ok, encoded} = Jido.Signal.Codec.serialize(signal, format: :erlang_term)
      assert {:ok, decoded} = Jido.Signal.Codec.deserialize(encoded, format: :erlang_term)
      assert decoded.data == data
    end

    test "keeps JSON-safe values in data" do
      data = %{"message" => "hello", "items" => [1, true, nil]}
      signal = Signal.new!("test.json", data, source: "/test")

      assert Jido.Signal.Codec.to_map(signal)["data"] == data
      refute Map.has_key?(Jido.Signal.Codec.to_map(signal), "data_base64")
    end

    test "keeps explicit null data in JSON" do
      signal = Signal.new!("test.null", nil, source: "/test")

      assert {:ok, json} = Jido.Signal.Codec.serialize(signal)
      assert Map.fetch(Jason.decode!(json), "data") == {:ok, nil}
      assert {:ok, ^signal} = Jido.Signal.Codec.deserialize(json)
    end

    test "rejects invalid or ambiguous data_base64" do
      wire = %{
        "specversion" => "1.0",
        "id" => "binary-1",
        "source" => "/test",
        "type" => "test.binary"
      }

      assert {:error, error} = Jido.Signal.Codec.from_map(Map.put(wire, "data_base64", "not-base64"))
      assert error =~ "valid Base64"

      encoded = Base.encode64("value")

      assert {:error, error} =
               Jido.Signal.Codec.from_map(Map.merge(wire, %{"data" => "value", "data_base64" => encoded}))

      assert error =~ "mutually exclusive"
    end

    test "does not interpret data_base64 as an Erlang term" do
      encoded_function = :erlang.term_to_binary(&System.cmd/3)

      wire = %{
        "specversion" => "1.0",
        "id" => "function-bytes",
        "source" => "/test",
        "type" => "test.binary",
        "data_base64" => Base.encode64(encoded_function)
      }

      assert {:ok, signal} = Jido.Signal.Codec.from_map(wire)
      assert signal.data == encoded_function
      refute is_function(signal.data)
    end
  end

  describe "boundary and options" do
    test "validates the decoded Signal envelope" do
      json = ~s({"specversion":"1.0","id":"1","source":"","type":"test.created"})

      assert {:error, error} = Jido.Signal.Codec.deserialize(json)
      assert error =~ "source"
    end

    test "rejects non-Signal input and unsupported formats" do
      assert {:error, {:invalid_signal, _message}} = SignalCodec.serialize(%{"type" => "test"})
      assert {:error, {:invalid_signal, _message}} = SignalCodec.serialize([:not_a_signal])
      assert {:error, {:unsupported_format, :msgpack}} = Jido.Signal.Codec.serialize([], format: :msgpack)
    end

    test "rejects invalid option and decoded payload shapes" do
      signal = Signal.new!(type: "test.created", source: "/test")

      assert {:error, {:invalid_options, "expected a keyword list"}} =
               SignalCodec.serialize(signal, %{})

      assert {:error, {:invalid_payload, "expected a binary"}} =
               SignalCodec.deserialize(:not_binary)

      assert {:error, {:invalid_options, "expected a keyword list"}} =
               SignalCodec.deserialize("{}", %{})

      assert {:error, {:invalid_wire_data, message}} =
               SignalCodec.deserialize("[1]")

      assert message =~ "expected a map"

      assert {:error, {:invalid_options, "expected a keyword list"}} =
               SignalCodec.serialize(signal, [:invalid])

      assert {:error, {:invalid_options, "expected a keyword list"}} =
               SignalCodec.deserialize("{}", [:invalid])
    end

    test "rejects an invalid payload limit" do
      signal = Signal.new!(type: "test.created", source: "/test")

      assert {:error, {:invalid_max_payload_bytes, -1}} =
               SignalCodec.serialize(signal, max_payload_bytes: -1)

      assert {:error, {:invalid_max_payload_bytes, :infinity}} =
               SignalCodec.deserialize("{}", max_payload_bytes: :infinity)
    end

    test "normalizes an unexpected canonical map failure" do
      signal = Signal.new!(type: "test.created", source: "/test")

      assert {:error, {:serialization_failed, message}} =
               SignalCodec.serialize(%{signal | extensions: :invalid})

      assert is_binary(message)
    end

    test "enforces the payload size for encode and decode" do
      signal = Signal.new!(type: "test.created", source: "/test")
      assert {:ok, json} = Jido.Signal.Codec.serialize(signal)

      assert {:error, {:payload_too_large, encode_size, 10}} =
               Jido.Signal.Codec.serialize(signal, max_payload_bytes: 10)

      assert {:error, {:payload_too_large, size, 10}} =
               Jido.Signal.Codec.deserialize(json, max_payload_bytes: 10)

      assert encode_size == byte_size(json)
      assert size == byte_size(json)
    end

    test "reads the application payload limit" do
      signal = Signal.new!(type: "test.created", source: "/test")
      assert {:ok, json} = Jido.Signal.Codec.serialize(signal)

      previous = Application.get_env(:jido, :max_payload_bytes)
      Application.put_env(:jido, :max_payload_bytes, 10)

      on_exit(fn ->
        if previous do
          Application.put_env(:jido, :max_payload_bytes, previous)
        else
          Application.delete_env(:jido, :max_payload_bytes)
        end
      end)

      assert {:error, {:payload_too_large, _size, 10}} = Jido.Signal.Codec.serialize(signal)
      assert {:error, {:payload_too_large, _size, 10}} = Jido.Signal.Codec.deserialize(json)
    end

    test "serialize!/2 returns a binary" do
      signal = Signal.new!(type: "test.created", source: "/test")
      assert is_binary(Jido.Signal.Codec.serialize!(signal))
    end

    test "rejects compressed Erlang terms before expansion" do
      wire = %{
        "specversion" => "1.0",
        "id" => "compressed",
        "source" => "/test",
        "type" => "test.compressed",
        "data" => String.duplicate("x", 1_000_000)
      }

      compressed = :erlang.term_to_binary(wire, compressed: 9)

      assert {:error, {:erlang_term_decode_failed, message}} =
               Jido.Signal.Codec.deserialize(compressed, format: :erlang_term)

      assert message =~ "compressed"
    end

    test "rejects maps with atom keys at the JSON boundary" do
      signal = Signal.new!("test.atom-keys", %{value: 1}, source: "/test")

      assert {:error, {:json_encode_failed, message}} = Jido.Signal.Codec.serialize(signal)
      assert message =~ "JSON values"

      tuple_signal = Signal.new!("test.tuple", {:one, :two}, source: "/test")
      assert {:error, {:json_encode_failed, _message}} = Jido.Signal.Codec.serialize(tuple_signal)
    end
  end

  test "uses the exact canonical Erlang size at the decoded size boundary" do
    signal = Signal.new!(type: "test.term", source: "/test", data: :éééé)
    wire = Jido.Signal.Codec.to_map(signal)
    legacy = :erlang.term_to_binary(wire, minor_version: 0)
    canonical = :erlang.term_to_binary(wire)
    input_size = byte_size(legacy)
    output_size = byte_size(canonical)
    assert input_size < output_size

    assert {:error, {:payload_too_large, ^output_size, ^input_size}} =
             Jido.Signal.Codec.deserialize(legacy, format: :erlang_term, max_payload_bytes: input_size)

    assert {:ok, ^signal} =
             Jido.Signal.Codec.deserialize(legacy, format: :erlang_term, max_payload_bytes: output_size)

    for data <- [:binary.copy("x", 131_072), %{blob: <<255>>, nested: [{:ok, [1, 2, 3]}]}] do
      signal = Signal.new!(type: "test.term", source: "/test", data: data)
      assert {:ok, encoded} = Jido.Signal.Codec.serialize(signal, format: :erlang_term)
      size = byte_size(encoded)

      assert {:ok, ^signal} =
               Jido.Signal.Codec.deserialize(encoded, format: :erlang_term, max_payload_bytes: size)

      assert {:error, {:payload_too_large, ^size, limit}} =
               Jido.Signal.Codec.deserialize(encoded, format: :erlang_term, max_payload_bytes: size - 1)

      assert limit == size - 1
    end
  end

  test "preserves UTF-8 and invalid byte sequences at both binary boundaries" do
    values = [
      "",
      "ASCII",
      "café 日本語 😀",
      :binary.copy("a", 131_072),
      :binary.copy("日本語", 8_192),
      :binary.copy("😀", 8_192),
      <<0xC0, 0xAF>>,
      <<0xED, 0xA0, 0x80>>,
      <<0xF4, 0x90, 0x80, 0x80>>,
      <<0xE2, 0x82>>,
      :binary.copy("a", 131_072) <> <<255>>
    ]

    boundaries = for n <- 0..15, suffix <- ["é😀text", <<255>>], do: :binary.copy("a", n) <> suffix

    for data <- values ++ boundaries do
      signal = Signal.new!(type: "test.text", source: "/test", data: data)
      wire = Jido.Signal.Codec.to_map(signal)
      assert Map.has_key?(wire, "data") == String.valid?(data)
      assert Map.has_key?(wire, "data_base64") == not String.valid?(data)
      assert {:ok, ^signal} = Jido.Signal.Codec.from_map(wire)
      assert {:ok, json} = Jido.Signal.Codec.serialize(signal)
      assert {:ok, ^signal} = Jido.Signal.Codec.deserialize(json)
    end

    signal = Signal.new!(type: "test.text", source: "/test", data: %{"text" => <<255>>})
    assert {:error, {:json_encode_failed, _}} = Jido.Signal.Codec.serialize(signal)
  end

  describe "legacy input" do
    test "normalizes supported v2 wire values" do
      json =
        Jason.encode!(%{
          "specversion" => "1.0.2",
          "jido_schema_version" => 1,
          "id" => "legacy-1",
          "source" => "/test",
          "type" => "test.created"
        })

      assert {:ok, signal} = Jido.Signal.Codec.deserialize(json)
      assert signal.specversion == "1.0"
      refute Map.has_key?(Jido.Signal.Codec.to_map(signal), "jido_schema_version")
    end

    test "rejects unsupported v2 wire markers" do
      json =
        Jason.encode!(%{
          "specversion" => "1.0",
          "jido_schema_version" => 999,
          "id" => "legacy-999",
          "source" => "/test",
          "type" => "test.created"
        })

      assert {:error, error} = Jido.Signal.Codec.deserialize(json)
      assert error =~ "unsupported jido_schema_version 999"
    end
  end
end
