defmodule Jido.Codec.IndexTest do
  use ExUnit.Case, async: true

  alias Jido.Codec.Index

  test "indexes decoder versions and the one current encoder for a target" do
    index =
      Index.new!([
        %{type: "example", vsn: 2, module: List, target: nil},
        %{type: "example", vsn: 1, module: String, target: URI}
      ])

    assert Index.versions(index, "example") == [1, 2]
    assert Index.codec(index, "example", 1) == {:ok, String}
    assert Index.codec(index, "example", 2) == {:ok, List}
    assert Index.codec(index, "example", 3) == {:error, :unknown_codec}
    assert Index.encoder(index, %URI{}) == {:ok, String}
    assert Index.encoder(index, :other) == {:error, :unknown_encoder}
  end

  test "rejects duplicate routes and encoder targets" do
    assert {:error, {:duplicate_codec, {"example", 1}}} =
             Index.new([
               %{type: "example", vsn: 1, module: String},
               %{type: "example", vsn: 1, module: List}
             ])

    assert {:error, {:duplicate_encoder_target, URI}} =
             Index.new([
               %{type: "one", vsn: 1, module: String, target: URI},
               %{type: "two", vsn: 1, module: List, target: URI}
             ])
  end
end
