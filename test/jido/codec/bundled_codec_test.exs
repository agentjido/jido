defmodule Jido.Codec.BundledCodecTest do
  use Covenant.Case, component: "jido_action.authoring", async: false

  @moduletag obligation: "jido_action.authoring.I4"

  alias Jido.Catalog
  alias Jido.Catalog.Discovery
  alias Jido.Codec.Issue
  alias Jido.Flow
  alias Jido.Flow.Ref

  defmodule Echo do
    use Jido.Action,
      id: "tests/actions/bundled-codec-echo",
      name: "bundled_codec_echo"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule StoredAgent do
    use Jido.Agent,
      id: "tests/agents/bundled-codec",
      name: "bundled_codec_agent"
  end

  setup do
    publication = :persistent_term.get({:jido, :catalog}, :not_ready)
    :persistent_term.erase({:jido, :catalog})

    on_exit(fn ->
      if publication == :not_ready,
        do: :persistent_term.erase({:jido, :catalog}),
        else: :persistent_term.put({:jido, :catalog}, publication)
    end)

    :ok
  end

  test "selects only exact bundled document types and versions" do
    assert {:ok, Jido.Agent.Codec} =
             Discovery.bundled_codec("jido.agent.definition", 1)

    assert {:ok, Jido.Flow.Codec} = Discovery.bundled_codec("jido.flow", 2)

    assert {:error, [%Issue{code: :invalid_document_type, path: ["type"]}]} =
             Discovery.bundled_codec(nil, 1)

    assert {:error, [%Issue{code: :invalid_document_type, path: ["type"]}]} =
             Discovery.bundled_codec(<<255>>, 1)

    assert {:error, [%Issue{code: :invalid_document_vsn, path: ["vsn"]}]} =
             Discovery.bundled_codec("jido.flow", 0)

    assert {:error,
            [
              %Issue{
                code: :unsupported_document,
                path: ["type"],
                details: %{
                  type: "unknown.document",
                  vsn: 1,
                  supported_vsns: []
                }
              }
            ]} = Discovery.bundled_codec("unknown.document", 1)

    assert {:error,
            [
              %Issue{
                code: :unsupported_document,
                path: ["vsn"],
                details: %{
                  type: "jido.flow",
                  vsn: 1,
                  supported_vsns: [2]
                }
              }
            ]} = Discovery.bundled_codec("jido.flow", 1)
  end

  test "decodes bundled documents with an explicit Catalog and no publication" do
    catalog = catalog()
    flow = flow()
    definition = StoredAgent.definition()

    assert {:ok, flow_json} = Jido.Codec.encode_json(flow, catalog: catalog)
    assert {:ok, agent_document} = Jido.Codec.encode(definition, catalog: catalog)
    refute Discovery.ready?()

    assert {:ok, flow_codec} = Discovery.bundled_codec("jido.flow", 2)

    assert {:ok, ^flow} =
             Jido.Codec.decode_json(flow_json, catalog: catalog, codec: flow_codec)

    assert {:ok, agent_codec} =
             Discovery.bundled_codec("jido.agent.definition", 1)

    assert {:ok, ^definition} =
             Jido.Codec.decode(agent_document, catalog: catalog, codec: agent_codec)
  end

  defp catalog do
    manifests =
      Enum.map([Echo, StoredAgent], fn module ->
        Jido.Catalog.Manifest.new!(module, :jido, module.__jido_catalog_manifest__())
      end)

    Catalog.new!(manifests)
  end

  defp flow do
    Flow.new!(%{
      name: "bundled_codec_flow",
      components: [%{kind: :step, name: "echo", action: Echo}],
      output: Ref.result("echo")
    })
  end
end
