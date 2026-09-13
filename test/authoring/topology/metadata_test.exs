Code.require_file("../support/compiler.exs", __DIR__)

defmodule JidoTest.Authoring.Topology.MetadataTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.Topology
  alias Jido.Topology.{Builder, Codec}
  alias JidoTest.Authoring.Compiler
  alias JidoTest.Authoring.Topology.Fixtures
  @fixtures Path.expand("../support/topology/fixtures", __DIR__)

  test "metadata preserves atom, string, and mixed keys through every form and JSON" do
    assert {_, []} = Compiler.compile_file(Path.join(@fixtures, "metadata_maps.exs"))

    for {module, metadata} <- [
          {Fixtures.AtomMetadata, %{case: "atom"}},
          {Fixtures.StringMetadata, %{"case" => "string"}},
          {Fixtures.MixedMetadata, %{"case" => "string", :case => "atom"}}
        ] do
      attrs = %{name: "metadata_maps", metadata: metadata}
      expected = Topology.new!(attrs)
      assert expected.metadata === metadata

      for definition <- [
            module.topology(),
            Topology.new!(Map.to_list(attrs)),
            Builder.build!(Builder.new(attrs)),
            Builder.new(name: "metadata_maps") |> Builder.metadata(metadata) |> Builder.build!(),
            Builder.build!(Builder.new(module))
          ] do
        assert definition === expected
        assert {:ok, document, registry} = Codec.encode(definition)
        assert {:ok, ^expected} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
      end
    end
  end

  test "data forms reject non-map and runtime metadata" do
    for metadata <- [
          nil,
          false,
          42,
          "invalid",
          [],
          [case: "invalid"],
          ~D[2026-09-13],
          %{pid: self()}
        ] do
      attrs = %{name: "invalid_metadata", metadata: metadata}

      for result <- [
            Topology.new(attrs),
            Topology.new(Map.to_list(attrs)),
            attrs |> Builder.new() |> Builder.build(),
            Builder.new(name: "invalid_metadata") |> Builder.metadata(metadata) |> Builder.build()
          ] do
        assert {:error, %Jido.Error.ValidationError{}} = result
      end
    end
  end

  for source <- ~w(metadata_nil metadata_list metadata_struct metadata_runtime) do
    @source source
    test "block metadata rejects #{@source}" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          Compiler.compile_file(Path.join(@fixtures, "invalid/#{@source}.exs"))
        end

      assert error.path == [:topology]
      assert Exception.message(error) =~ "metadata"
    end
  end
end
