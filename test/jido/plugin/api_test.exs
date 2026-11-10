defmodule Jido.Plugin.ApiTest do
  use Covenant.Case, component: "jido.plugin", async: true

  import Jido.Test.PublicAPI

  alias Jido.Plugin

  alias Jido.Plugin.{
    Context,
    Init,
    Input,
    Manifest,
    Normalizer,
    Spec
  }

  alias Jido.Plugin.Context.{Admission, Commit, Persistence}

  @tag obligation: ["jido.plugin.I1", "jido.plugin.I8", "jido.plugin.I9"]
  test "the documented Plugin API contains only the public authoring and context surface" do
    assert documented_api(Plugin) == [{:macro, :__using__, 1}]
    assert documented_api(Input) == []
    assert documented_api(Init) == [{:function, :schema, 0}]
    assert documented_api(Context) == [{:function, :schema, 1}]
    assert documented_api(Admission) == []
    assert documented_api(Commit) == []
    assert documented_api(Persistence) == [{:function, :schema, 0}, {:function, :validate, 1}]

    for module <- [Plugin, Context, Admission, Commit, Persistence, Input, Init] do
      assert public_module?(module)
    end

    for module <- [Manifest, Normalizer, Spec] do
      refute public_module?(module)
    end
  end

  @tag obligation: ["jido.plugin.I8", "jido.plugin.I9"]
  test "callback records keep their exact read-only fields" do
    assert fields(Admission) == [
             :agent_id,
             :agent_module,
             :caller_context,
             :plugin,
             :plugin_state,
             :prepared_input,
             :signal,
             :state_version
           ]

    assert fields(Commit) == [
             :agent_id,
             :agent_module,
             :jido,
             :partition,
             :plugin,
             :plugin_state,
             :state_version,
             :turn_id
           ]
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
        {:prepare_outbound, 4},
        {:quiesce, 2},
        {:reduce, 2},
        {:resume, 2},
        {:select_route, 2},
        {:state_spec, 1},
        {:validate_options, 1}
      ]
      |> Enum.sort()

    assert Plugin.behaviour_info(:callbacks) |> Enum.sort() == expected
    assert Plugin.behaviour_info(:optional_callbacks) |> Enum.sort() == expected
  end

  defp fields(module) do
    module
    |> struct()
    |> Map.from_struct()
    |> Map.keys()
    |> Enum.sort()
  end
end
