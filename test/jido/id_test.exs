defmodule Jido.IdTest do
  use ExUnit.Case, async: true

  alias Jido.Id

  describe "uuid7/0" do
    test "generates a valid UUIDv7 with a timestamp" do
      uuid = Id.uuid7()

      assert Id.uuid7?(uuid)
      assert is_integer(Id.uuid7_timestamp(uuid))
      assert Id.uuid7_timestamp(uuid) >= 0
      assert <<_timestamp::48, 7::4, _random_a::12, 2::2, _random_b::62>> = decode(uuid)
    end

    test "generates unique identifiers" do
      ids = Enum.map(1..1_000, fn _number -> Id.uuid7() end)
      assert length(Enum.uniq(ids)) == 1_000
    end
  end

  describe "uuid7?/1" do
    test "accepts RFC 9562 and mixed-case UUIDv7 values" do
      uuid = "017f22e2-79b0-7cc3-98c4-dc0c0c07398f"

      assert Id.uuid7?(uuid)
      assert Id.uuid7?(String.upcase(uuid))
    end

    test "rejects invalid shape, version, and variant values" do
      refute Id.uuid7?("not-a-uuid")
      refute Id.uuid7?("017f22e279b07cc398c4dc0c0c07398f")
      refute Id.uuid7?("017f22e2-79b0-6cc3-98c4-dc0c0c07398f")
      refute Id.uuid7?("017f22e2-79b0-7cc3-78c4-dc0c0c07398f")
      refute Id.uuid7?(123)
      refute Id.uuid7?(nil)
    end
  end

  describe "UUIDv7 reading and comparison" do
    test "extracts the timestamp" do
      uuid = "017f22e2-79b0-7cc3-98c4-dc0c0c07398f"
      assert Id.uuid7_timestamp(uuid) == 1_645_557_742_000
    end

    test "compares complete UUID values" do
      older = "017f22e2-79b0-7000-8000-000000000000"
      newer = "017f22e2-79b1-7000-8000-000000000000"
      same_time = "017f22e2-79b0-7000-8000-000000000001"

      assert Id.compare_uuid7(older, newer) == :lt
      assert Id.compare_uuid7(newer, older) == :gt
      assert Id.compare_uuid7(older, older) == :eq
      assert Id.compare_uuid7(older, same_time) == :lt
      assert Id.compare_uuid7(same_time, older) == :gt
      assert Id.uuid7_timestamp(older) == Id.uuid7_timestamp(same_time)
    end

    test "treats mixed-case forms of one UUID as equal" do
      uuid = "017f22e2-79b0-7cc3-98c4-dc0c0c07398f"

      assert Id.compare_uuid7(uuid, String.upcase(uuid)) == :eq
      assert Id.uuid7_timestamp(uuid) == Id.uuid7_timestamp(String.upcase(uuid))
    end

    test "raises a clear error for invalid input" do
      assert_raise ArgumentError, "expected a valid UUIDv7 identifier", fn ->
        Id.uuid7_timestamp("not-a-uuid")
      end
    end
  end

  describe "uuid8/1" do
    test "formats deterministic bytes with the UUIDv8 version and variant" do
      assert Id.uuid8(<<0::128>>) == "00000000-0000-8000-8000-000000000000"

      digest = :crypto.hash(:sha256, "stable input")
      assert Id.uuid8(digest) == Id.uuid8(digest)
      assert <<_prefix::48, 8::4, _custom_a::12, 2::2, _custom_b::62>> = decode(Id.uuid8(digest))
    end

    test "rejects a value that is shorter than 16 bytes" do
      assert_raise ArgumentError, "expected at least 16 bytes for a UUIDv8 identifier", fn ->
        Id.uuid8(<<0::120>>)
      end
    end
  end

  defp decode(uuid) do
    {:ok, raw} = uuid |> String.replace("-", "") |> Base.decode16(case: :mixed)
    raw
  end
end
