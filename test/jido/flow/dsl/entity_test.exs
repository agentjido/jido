defmodule Jido.Flow.DSL.EntityTest do
  use ExUnit.Case, async: true

  alias Jido.Flow.DSL.{Choice, ChoiceOption, Iterate, IterateState, Otherwise}

  test "entity definitions retain their owning imports and nested cardinality" do
    [section] = Jido.Flow.DSL.Schema.sections()

    for entity <- section.entities do
      assert apply(entity.target, :entity, []) == entity

      for {_key, children} <- entity.entities, child <- children do
        assert apply(child.target, :entity, []) == child
      end
    end

    assert Choice.entity().imports == [Jido.Flow.DSL.ChoiceMacros]
    assert Choice.entity().singleton_entity_keys == [:fallback]

    assert Choice.entity().entities == [
             options: [ChoiceOption.entity()],
             fallback: [Otherwise.entity()]
           ]

    assert Iterate.entity().imports == [Jido.Flow.DSL.IterateMacros]
    assert Iterate.entity().singleton_entity_keys == [:state]
    assert Iterate.entity().entities == [state: [IterateState.entity()]]
  end

  test "generated structs keep required fields optional until Spark checks a declaration" do
    module = Module.concat(__MODULE__, "Probe#{System.unique_integer([:positive])}")

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
    end)

    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          @moduledoc false

          use Jido.Flow.DSL.Entity,
            name: :probe,
            node?: true,
            args: [:value, :__source__],
            schema: [
              value: [type: :quoted, required: true],
              enabled: [type: :boolean, default: true]
            ],
            entities: [
              items: [unquote(ChoiceOption).entity()],
              fallback: [unquote(Otherwise).entity()]
            ],
            singleton_entity_keys: [:fallback]
        end
      end
    )

    assert %{
             value: nil,
             enabled: true,
             items: [],
             fallback: nil,
             needs: [],
             meta: %{},
             __source__: %{},
             __identifier__: nil,
             __spark_metadata__: nil
           } = struct(module)

    assert Keyword.fetch!(apply(module, :entity, []).schema, :value) == [
             type: :quoted,
             required: true
           ]
  end
end
