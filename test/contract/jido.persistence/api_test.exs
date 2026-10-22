defmodule JidoTest.Persistence.ApiTest do
  use Covenant.Case, component: "jido.persistence", async: true

  alias Jido.Persistence
  alias Jido.Persistence.{Adapter, Plugin, S3, Snapshot, Store}
  alias Jido.Persistence.Plugin.Context

  @tag obligation: [
         "jido.persistence.I1",
         "jido.persistence.I6",
         "jido.persistence.I10",
         "jido.persistence.I12"
       ]
  test "the documented public API excludes persistence implementation helpers" do
    assert documented_functions(Persistence) == [
             delete_agent: 4,
             load_agent: 4,
             load_agent_with_revision: 4,
             resolve_config: 2,
             restore: 2,
             save_agent: 3,
             snapshot: 2,
             upgrade: 3
           ]

    assert documented_functions(Store) == [compare_and_swap: 4, open: 1, read: 2]
    assert documented_functions(Context) == [schema: 0, validate: 1]
    assert documented_functions(Plugin) == []

    assert public_module?(Persistence)
    assert public_module?(Adapter)
    assert public_module?(Store)
    assert public_module?(Plugin)
    assert public_module?(Context)
    assert public_module?(S3)
    refute public_module?(Snapshot)
  end

  @tag obligation: ["jido.persistence.I1", "jido.persistence.I3", "jido.persistence.I4"]
  test "the Adapter behavior has one required read and atomic write contract" do
    assert Adapter.behaviour_info(:callbacks) |> Enum.sort() ==
             [
               compare_and_swap: 4,
               delete: 2,
               get: 2,
               put: 3,
               validate_options: 1
             ]

    assert Adapter.behaviour_info(:optional_callbacks) |> Enum.sort() ==
             [delete: 2, put: 3, validate_options: 1]
  end

  @tag obligation: ["jido.persistence.I10", "jido.persistence.I11"]
  test "the public Plugin context accepts only its exact bounded shape" do
    context = %Context{
      plugin: __MODULE__,
      plugin_vsn: 1,
      record_format: 1,
      direction: :dump,
      reason: self()
    }

    assert {:ok, ^context} = Zoi.parse(Context.schema(), context)
    assert {:ok, ^context} = Context.validate(context)

    assert {:error,
            %Jido.Error.ValidationError{
              subject: Context,
              details: %{value: nil}
            }} = Context.validate(nil)

    assert {:error,
            %Jido.Error.ValidationError{
              subject: Context,
              details: %{issues: issues}
            }} = Context.validate(%{context | plugin: nil})

    assert [_issue | _rest] = issues

    for invalid <- [
          %{context | plugin_vsn: 0},
          %{context | record_format: 0},
          %{context | direction: :other},
          Map.put(context, :extra, true)
        ] do
      assert {:error, %Jido.Error.ValidationError{subject: Context}} = Context.validate(invalid)
    end
  end

  defp documented_functions(module) do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)

    docs
    |> Enum.flat_map(fn
      {{:function, name, arity}, _, _, doc, _} when doc not in [:hidden, :none] ->
        [{name, arity}]

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
