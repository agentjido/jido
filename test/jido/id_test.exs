defmodule JidoTest.IDTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Jido.ID

  @uuid7_regex ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  describe "uuid7/0" do
    test "generates lowercase RFC 9562 UUIDv7 strings" do
      assert ID.uuid7() =~ @uuid7_regex
    end

    test "encodes current Unix millisecond timestamp, version, variant, and random fields" do
      before_ms = System.system_time(:millisecond)
      uuid = ID.uuid7()
      after_ms = System.system_time(:millisecond)

      decoded = decode_uuid7(uuid)

      assert decoded.timestamp in before_ms..after_ms
      assert decoded.version == 7
      assert decoded.variant == 2
      assert decoded.rand_a in 0..0xFFF
      assert decoded.rand_b in 0..0x3FFFFFFFFFFFFFFF
    end

    test "generates unique IDs" do
      ids = for _index <- 1..1000, do: ID.uuid7()

      assert length(Enum.uniq(ids)) == 1000
    end
  end

  describe "uuid7/2" do
    test "matches RFC 9562 UUIDv7 example bit layout" do
      timestamp = 0x017F22E279B0
      rand_a = 0x0CC3
      rand_b = 0b01 <<< 60 ||| 0x8C4DC0C0C07398F
      random_bytes = <<rand_a::12, rand_b::62, 0::6>>

      assert ID.uuid7(timestamp, random_bytes) ==
               "017f22e2-79b0-7cc3-98c4-dc0c0c07398f"
    end

    test "supports minimum and maximum representable values" do
      assert ID.uuid7(0, <<0::80>>) == "00000000-0000-7000-8000-000000000000"

      assert ID.uuid7(0xFFFFFFFFFFFF, :binary.copy(<<0xFF>>, 10)) ==
               "ffffffff-ffff-7fff-bfff-ffffffffffff"
    end

    test "preserves lexical timestamp ordering with fixed random bytes" do
      random_bytes = <<0::80>>

      assert ID.uuid7(1, random_bytes) < ID.uuid7(2, random_bytes)
    end

    test "uses the high 74 random bits and ignores only the low 6 padding bits" do
      rand_a = 0x0ABC
      rand_b = 0x123456789ABCDEF

      uuid_with_zero_padding = ID.uuid7(42, <<rand_a::12, rand_b::62, 0::6>>)
      uuid_with_one_padding = ID.uuid7(42, <<rand_a::12, rand_b::62, 0b111111::6>>)

      assert uuid_with_zero_padding == uuid_with_one_padding

      decoded = decode_uuid7(uuid_with_zero_padding)

      assert decoded.rand_a == rand_a
      assert decoded.rand_b == rand_b
    end

    test "rejects timestamps outside the 48-bit UUIDv7 range" do
      assert_raise FunctionClauseError, fn ->
        ID.uuid7(0x1_0000_0000_0000, <<0::80>>)
      end

      assert_raise FunctionClauseError, fn ->
        ID.uuid7(-1, <<0::80>>)
      end

      assert_raise FunctionClauseError, fn ->
        ID.uuid7(1.0, <<0::80>>)
      end
    end

    test "rejects random inputs that are not 80 bits" do
      assert_raise FunctionClauseError, fn ->
        ID.uuid7(0, <<0::72>>)
      end

      assert_raise FunctionClauseError, fn ->
        ID.uuid7(0, <<0::88>>)
      end

      assert_raise FunctionClauseError, fn ->
        ID.uuid7(0, :not_binary)
      end
    end
  end

  defp decode_uuid7(uuid) do
    {:ok, <<timestamp::48, version::4, rand_a::12, variant::2, rand_b::62>>} =
      uuid
      |> String.replace("-", "")
      |> Base.decode16(case: :mixed)

    %{
      timestamp: timestamp,
      version: version,
      rand_a: rand_a,
      variant: variant,
      rand_b: rand_b
    }
  end
end
