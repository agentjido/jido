Code.require_file("../support/compiler.exs", __DIR__)

defmodule JidoTest.Authoring.Agents.MetadataTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.Agent
  alias Jido.Agent.{Builder, Codec}
  alias JidoTest.Authoring.Compiler
  alias JidoTest.Authoring.Agents.Fixtures
  @fixtures Path.expand("../support/agents/fixtures", __DIR__)

  test "metadata keeps atom, string, and mixed keys across authoring forms and JSON" do
    assert {_, []} = Compiler.compile_file(Path.join(@fixtures, "metadata_maps.exs"))

    for {module, metadata} <- [
          {Fixtures.AtomMetadata, %{case: "atom-key"}},
          {Fixtures.StringMetadata, %{"case" => "string-key"}},
          {Fixtures.MixedMetadata,
           %{"case" => "string-key", :case => "atom-key", :nested => %{"enabled" => false}}}
        ] do
      attrs = %{module: module, name: "metadata_maps", vsn: 1, metadata: metadata}
      assert {:ok, expected} = Agent.new(attrs)
      assert expected.metadata === metadata

      for definition <- [
            module.definition(),
            Agent.new!(Map.to_list(attrs)),
            Builder.build!(Builder.new(attrs)),
            attrs
            |> Map.delete(:metadata)
            |> Builder.new()
            |> Builder.metadata(metadata)
            |> Builder.build!(),
            Builder.build!(Builder.new(module))
          ] do
        assert definition === expected
        assert {:ok, document, registry} = Codec.encode(definition)
        assert {:ok, ^expected} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
      end
    end
  end

  test "data forms reject metadata structs and non-map values" do
    for metadata <- [~D[2026-09-13], nil, false, 42, "invalid", [], [case: "invalid"]] do
      attrs = %{name: "invalid_metadata", metadata: metadata}

      for result <- [
            Agent.new(attrs),
            Agent.new(Map.to_list(attrs)),
            attrs |> Builder.new() |> Builder.build(),
            Builder.new(name: "invalid_metadata") |> Builder.metadata(metadata) |> Builder.build()
          ] do
        assert {:error, %Jido.Error.ValidationError{}} = result
      end
    end
  end

  for file <- ["metadata_struct", "metadata_list", "metadata_nil"] do
    @file_path "invalid/#{file}.exs"
    test "invalid metadata source: #{file}" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          Compiler.compile_file(Path.join(@fixtures, @file_path))
        end

      assert error.path == [:agent]
      assert Exception.message(error) =~ "Agent metadata must be a map"
    end
  end
end
