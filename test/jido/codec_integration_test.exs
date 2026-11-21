defmodule Jido.CodecIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Catalog
  alias Jido.Codec.{Index, Reference}

  defmodule Extension do
    use Jido.Plugin, id: "tests/plugins/authoring", vsn: 2
  end

  defmodule Plugin do
    use Jido.Plugin, id: "tests/plugins/sample", vsn: 3
    def state_spec(_opts), do: :none
  end

  defmodule ReferencedAction do
    use Jido.Action,
      name: "referenced_action"

    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule ReferencedExtension do
    use Jido.Plugin, id: "tests/plugins/referenced"

    @impl Jido.Agent.Extension
    def encode_authoring_data(%{target: target}, registry) do
      with {:ok, reference} <- Reference.encode(registry, target),
           do: {:ok, %{"target" => reference}}
    end

    @impl Jido.Agent.Extension
    def decode_authoring_data(%{"target" => reference} = data, registry)
        when map_size(data) == 1 do
      with {:ok, target} <- Reference.decode(registry, reference),
           do: {:ok, %{target: target}}
    end

    def decode_authoring_data(_data, _registry),
      do: Jido.Error.validation_result(:invalid_data, [], "Invalid referenced extension data")

    @impl Jido.Agent.Extension
    def derive_routes(%{target: target}) do
      [
        %{
          path: "referenced.request",
          handler: %{kind: :action, target: target},
          state: %{source: :output, path: []}
        }
      ]
    end
  end

  defmodule Agent do
    use Jido.Agent, name: "sample_agent", id: "tests/agents/sample"
  end

  defmodule Vocabulary do
    def __jido_catalog_manifest__ do
      %{
        id: "tests/schemas/sample-agent",
        vsn: 1,
        target: Agent.definition().schema
      }
    end
  end

  setup do
    registry = :persistent_term.get({:jido, :catalog}, :not_ready)

    on_exit(fn ->
      if registry == :not_ready,
        do: :persistent_term.erase({:jido, :catalog}),
        else: :persistent_term.put({:jido, :catalog}, registry)
    end)
  end

  test "Agent Plugins use the shared Catalog" do
    assert :ok =
             Jido.Catalog.Discovery.refresh(
               applications: [],
               modules: [
                 {Agent, :jido},
                 {Extension, :jido},
                 {Plugin, :jido},
                 {Vocabulary, :jido},
                 {Jido.Agent.Codec, :jido}
               ]
             )

    catalog = Jido.Catalog.Discovery.catalog()
    codecs = Jido.Catalog.Discovery.codec_index()

    assert %{target: Agent} =
             Catalog.get(catalog, "tests/agents/sample", 1)

    assert %{target: Extension} =
             Catalog.get(catalog, "tests/plugins/authoring", 2)

    assert %{target: Plugin} =
             Catalog.get(catalog, "tests/plugins/sample", 3)

    assert Index.codec(codecs, "jido.agent.definition", 1) ==
             {:ok, Jido.Agent.Codec}

    definition = Agent.definition()
    assert {:ok, document} = Jido.Codec.encode(definition, catalog: catalog)
    assert document["vsn"] == 1
    assert {:ok, ^definition} = Jido.Codec.decode(document, catalog: catalog)
  end

  test "the default scan includes core Jido when it is loaded" do
    assert :ok = Jido.Catalog.Discovery.refresh()

    assert Index.codec(Jido.Catalog.Discovery.codec_index(), "jido.agent.definition", 1) ==
             {:ok, Jido.Agent.Codec}
  end

  test "an extension can encode and decode typed Catalog references" do
    definition =
      Jido.Agent.define!(%{
        name: "referenced_extension_agent",
        routes: [
          %{
            path: "manual.request",
            handler: %{kind: :action, target: ReferencedAction},
            state: %{source: :output, path: []}
          }
        ],
        plugins: [
          %{
            id: ReferencedExtension.id(),
            provider: ReferencedExtension,
            vsn: ReferencedExtension.vsn(),
            data: %{target: ReferencedAction}
          }
        ]
      })

    catalog =
      Catalog.from_targets!(__MODULE__, :jido, %{
        {"tests/schemas/referenced-extension-agent", 1} => definition.schema,
        {"tests/plugins/referenced", 1} => ReferencedExtension,
        {"tests/actions/referenced", 1} => ReferencedAction
      })

    assert {:ok, document} =
             Jido.Codec.encode(definition, catalog: catalog, codec: Jido.Agent.Codec)

    assert get_in(document, ["definition", "plugins", Access.at(0), "data"]) == %{
             "target" => %{"id" => "tests/actions/referenced", "vsn" => 1}
           }

    assert [%{"path" => "manual.request"}] = document["definition"]["routes"]

    assert [%{path: "manual.request"}, %{path: "referenced.request"}] =
             definition.routes

    assert {:ok, ^definition} =
             Jido.Codec.decode(document, catalog: catalog, codec: Jido.Agent.Codec)

    restricted =
      Catalog.from_targets!(__MODULE__, :jido, %{
        {"tests/schemas/referenced-extension-agent", 1} => definition.schema,
        {"tests/plugins/referenced", 1} => ReferencedExtension
      })

    assert {:error, _issues} =
             Jido.Codec.decode(document, catalog: restricted, codec: Jido.Agent.Codec)
  end

  test "Agent and Plugin legacy JSON facades stay removed" do
    assert Code.ensure_loaded?(Jido.Agent.Codec)
    refute function_exported?(Jido.Agent, :to_json, 2)
    refute function_exported?(Jido.Agent, :from_json, 2)
    assert function_exported?(Jido.Agent.Codec, :encode, 2)
    assert function_exported?(Jido.Agent.Codec, :decode, 2)
    refute function_exported?(Jido.Agent.Codec, :from_json, 2)
    refute function_exported?(Jido.Plugin, :manifest, 1)
  end
end
