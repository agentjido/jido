defmodule Jido.AI.Agent.PluginContractTest do
  use Covenant.Case, component: "jido_ai.agent_authoring", async: true

  alias Jido.AI.Agent.Plugin
  alias Jido.AI.Reasoning.ReAct
  alias Jido.Test.AI.Tools.Add
  alias Jido.Catalog
  alias Jido.Catalog.Error, as: CatalogError

  @tag obligation: ["jido_ai.agent_authoring.I1", "jido_ai.agent_authoring.I3"]
  test "the Plugin normalizes one route and rejects invalid provider data" do
    assert %Jido.Plugin.Manifest{
             module: Plugin,
             agent: Plugin,
             option_keys: %{agent: [:reasoning, :defaults, :tools]}
           } = Plugin.__jido_plugin__()

    assert {:ok, %{tools: [Add], defaults: %{model: "contract:model"}} = prepared} =
             Plugin.prepare(%{}, reasoning: ReAct, defaults: %{model: "contract:model"}, tools: [Add])

    input = %Jido.Plugin.Input{prepared: prepared, runtime: nil}
    assert Plugin.prepared_tools(%{plugin_inputs: %{Plugin => input}}) == [Add]
    assert Plugin.prepared_defaults(%{plugin_inputs: %{Plugin => input}}) == %{model: "contract:model"}
    assert Plugin.prepared_tools(%{}) == []
    assert Plugin.prepared_defaults(%{}) == %{}

    assert {:ok, normalized} =
             Plugin.normalize(%{reasoning: ReAct, defaults: %{model: "contract:model"}, tools: [Add]})

    assert normalized == %{reasoning: ReAct, defaults: %{model: "contract:model"}, tools: [Add]}

    assert [route] = Plugin.derive_routes(normalized)
    assert route.path == "jido.ai.request"
    assert route.handler == %{kind: :flow, target: ReAct}
    assert route.defaults.model == "contract:model"

    assert {:error, %{code: :invalid_reasoning}} = Plugin.normalize(%{reasoning: String})
    assert {:error, %{code: :reserved_default}} = Plugin.normalize(%{reasoning: ReAct, defaults: %{input: "bad"}})
    assert {:error, %{code: :invalid_defaults}} = Plugin.normalize(%{reasoning: ReAct, defaults: []})

    assert {:error, %{code: :invalid_value, path: [:defaults, :model]}} =
             Plugin.normalize(%{reasoning: ReAct, defaults: %{model: %{}}})

    assert {:error, %{code: :invalid_tools}} = Plugin.normalize(%{reasoning: ReAct, tools: [:invalid]})
  end

  @tag obligation: ["jido_ai.agent_authoring.I1", "jido_ai.agent_authoring.I2"]
  test "the Plugin lowers either DSL declarations or provider data" do
    reasoning = %Plugin.Reasoning{target: ReAct, defaults: %{model: "contract:model"}}
    tool = %Plugin.Tool{target: Add}

    dsl = %{
      [:__ai__] => %{entities: [reasoning]},
      [:__ai__, :__tools__] => %{entities: [tool]}
    }

    assert {:ok, %{reasoning: ReAct, tools: [Add]}} = Plugin.lower(dsl, %{})
    assert {:error, %{code: :ambiguous_ai}} = Plugin.lower(dsl, %{reasoning: ReAct})

    assert {:ok, %{reasoning: ReAct, defaults: %{model: "provider:model"}}} =
             Plugin.lower(%{}, %{reasoning: ReAct, defaults: %{model: "provider:model"}})

    assert {:error, %{code: :reasoning_count}} = Plugin.lower(%{}, %{})

    assert {:error, %{code: :reasoning_count}} =
             Plugin.lower(%{[:__ai__] => %{entities: [reasoning, reasoning]}}, %{})
  end

  @tag obligation: "jido_ai.agent_authoring.I4"
  test "Plugin authoring data round-trips and returns located codec errors" do
    registry =
      Catalog.from_targets!(__MODULE__, :jido, %{
        {"contract/reasoning", 1} => {:flow, ReAct},
        {"contract/add", 1} => {:action, Add}
      })

    data = %{reasoning: ReAct, defaults: %{model: "contract:model"}, tools: [Add]}

    assert {:ok,
            %{
              "reasoning" => %{"id" => "contract/reasoning", "vsn" => 1},
              "config" => %{"model" => "contract:model"},
              "tools" => [%{"id" => "contract/add", "vsn" => 1}]
            } = document} = Plugin.encode_authoring_data(data, registry)

    assert {:ok, ^data} = Plugin.decode_authoring_data(document, registry)
    assert {:error, %{code: :invalid_document, path: []}} = Plugin.decode_authoring_data(:invalid, registry)

    assert {:error, %{code: :invalid_document, path: []}} =
             Plugin.decode_authoring_data(%{"reasoning" => %{}}, registry)

    assert {:error, %{code: :reference, path: ["reasoning", "id"]}} =
             Plugin.decode_authoring_data(%{document | "reasoning" => %{}}, registry)

    assert {:error, %{code: :invalid_tools, path: ["tools"]}} =
             Plugin.decode_authoring_data(%{document | "tools" => :invalid}, registry)

    assert {:error, %{code: :reference, path: ["tools", 0, "id"]}} =
             Plugin.decode_authoring_data(%{document | "tools" => [%{}]}, registry)

    assert {:error, _error} = Plugin.encode_authoring_data(%{data | reasoning: String}, registry)

    registry_without_tool =
      Catalog.from_targets!(__MODULE__, :jido, %{
        {"contract/reasoning", 1} => {:flow, ReAct}
      })

    assert {:error, %CatalogError{}} = Plugin.encode_authoring_data(data, registry_without_tool)

    assert {:error, %{code: :invalid_value, path: ["config", "model"]}} =
             Plugin.decode_authoring_data(%{document | "config" => %{"model" => %{}}}, registry)

    invalid_tool_registry =
      Catalog.from_targets!(__MODULE__, :jido, %{
        {"contract/reasoning", 1} => {:flow, ReAct},
        {"contract/invalid-tool", 1} => {:action, String}
      })

    invalid_tool_document = %{document | "tools" => [%{"id" => "contract/invalid-tool", "vsn" => 1}]}

    assert {:error, %{code: :invalid_tools, path: ["tools"]}} =
             Plugin.decode_authoring_data(invalid_tool_document, invalid_tool_registry)
  end
end
