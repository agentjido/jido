defmodule JidoTest.PluginContract.CodecTest do
  use Covenant.Case, component: "jido.plugin", async: true

  alias Jido.Plugin.Codec

  defmodule Package do
    use Jido.Plugin, id: "contract.codec", vsn: 2, option_keys: [agent: [:label]]

    @impl true
    def state_spec(_opts), do: {:codec_owned, Zoi.integer() |> Zoi.default(0)}
  end

  @tag obligation: "jido.plugin.I8"
  test "the document contains only a registered Plugin declaration" do
    declaration = {Package, label: "current"}

    assert {:ok, document, registry} = Codec.encode(declaration)
    assert Map.keys(document) |> Enum.sort() == ~w(module options type version)
    assert document["type"] == "jido.plugin"
    assert document["version"] == 1
    assert {:ok, ^declaration} = Codec.decode(document, registry)
    assert {:ok, spec} = Codec.decode_spec(document, registry)
    assert spec.module == Package
    assert spec.options == [label: "current"]
    refute Map.has_key?(document, "state")
    refute Map.has_key?(document, "runtime")

    assert {:ok, ^document} = Codec.encode(declaration, registry)
  end

  @tag obligation: "jido.plugin.I8"
  test "decode rejects malformed, unknown, and unregistered documents" do
    assert {:ok, document, registry} = Codec.encode(Package)

    invalid_documents = [
      Map.delete(document, "module"),
      Map.put(document, "extra", true),
      %{document | "type" => "other"},
      %{document | "version" => 2},
      %{document | "options" => :invalid}
    ]

    for invalid <- invalid_documents do
      assert {:error, _reason} = Codec.decode(invalid, registry)
    end

    assert {:error, _reason} = Codec.decode(document, %{})
    assert {:error, _reason} = Codec.decode_spec(%{document | "version" => 2}, registry)
  end
end
