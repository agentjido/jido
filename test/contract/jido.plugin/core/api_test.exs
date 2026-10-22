defmodule JidoTest.PluginContract.ApiTest do
  use Covenant.Case, component: "jido.plugin", async: true

  alias Jido.Plugin

  alias Jido.Plugin.{
    DirectiveContext,
    Error,
    Init,
    Input,
    Manifest,
    Normalizer,
    SignalContext,
    Spec
  }

  @tag obligation: ["jido.plugin.I1", "jido.plugin.I8", "jido.plugin.I9"]
  test "the documented Plugin API contains only the public authoring and context surface" do
    assert documented_api(Plugin) == [{:function, :state, 2}, {:macro, :__using__, 1}]
    assert documented_api(Input) == []
    assert documented_api(Init) == [{:function, :schema, 0}]
    assert documented_api(SignalContext) == [{:function, :schema, 0}]
    assert documented_api(DirectiveContext) == [{:function, :schema, 0}]

    for module <- [Plugin, Input, Init, SignalContext, DirectiveContext] do
      assert public_module?(module)
    end

    for module <- [Error, Manifest, Normalizer, Spec] do
      refute public_module?(module)
    end
  end

  @tag obligation: ["jido.plugin.I2", "jido.plugin.I8"]
  test "the Plugin behavior has one closed optional callback surface" do
    expected =
      [
        {:admit, 3},
        {:after_commit, 3},
        {:await_ready, 2},
        {:child_spec, 1},
        {:directives, 1},
        {:dispatch, 4},
        {:dump, 3},
        {:load, 3},
        {:prepare, 2},
        {:prepare_dispatch, 4},
        {:quiesce, 2},
        {:reduce, 2},
        {:resume, 2},
        {:state_spec, 1},
        {:validate_options, 1}
      ]
      |> Enum.sort()

    assert Plugin.behaviour_info(:callbacks) |> Enum.sort() == expected
    assert Plugin.behaviour_info(:optional_callbacks) |> Enum.sort() == expected
  end

  defp documented_api(module) do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)

    docs
    |> Enum.flat_map(fn
      {{kind, name, arity}, _, _, doc, _}
      when kind in [:function, :macro] and
             doc not in [:hidden, :none] ->
        [{kind, name, arity}]

      _other ->
        []
    end)
    |> Enum.sort()
  end

  defp public_module?(module) do
    {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(module)
    module_doc not in [:hidden, :none]
  end
end
