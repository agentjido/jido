defmodule Jido.Flow.ReduceTest do
  use ExUnit.Case, async: true

  alias Jido.Authoring.Registry
  alias Jido.Flow
  alias Jido.Flow.{Codec, Ref}

  defmodule Accumulate do
    use Jido.Action, name: "flow_reduce_accumulate"

    @impl true
    def run(%{accumulator: accumulator, item: item}, _context) do
      {:ok, %{total: accumulator.total + item}}
    end
  end

  defmodule Authored do
    use Jido.Flow, name: "reduce_values"

    flow do
      reduce("total",
        collection: input(:values),
        initial: %{total: 0},
        action: Accumulate,
        params: %{accumulator: accumulator(), index: item_index(), item: item()},
        timeout_ms: 500,
        retry: [max_attempts: 2]
      )

      output(result("total"))
    end
  end

  test "normalizes one ordered Reduce form" do
    flow =
      Flow.new!(%{
        name: "reduce_values",
        forms: %{
          total: %{
            type: :reduce,
            collection: Ref.input(:values),
            initial: %{total: 0},
            action: Accumulate,
            params: %{
              accumulator: %Ref{source: :accumulator},
              index: Ref.item_index(),
              item: Ref.item()
            }
          }
        },
        output: Ref.result(:total)
      })

    assert %Jido.Flow.Form.Reduce{} = flow.forms["total"]
  end

  test "DSL, map, and JSON authoring produce the same canonical Reduce form" do
    from_dsl = Authored.flow()
    from_map = reduce_flow()
    registry = registry()

    assert {:ok, document} = Codec.encode_document(from_map, registry)
    assert {:ok, from_json} = Codec.decode_document(document, registry)

    assert from_dsl == from_map
    assert from_json == from_map
    assert from_map.forms["total"].call.policy.retry.max_attempts == 2
    assert get_in(document, ["forms", Access.at(0), Access.at(1), "type"]) == "reduce"
  end

  test "keeps Reduce iterations inside one named graph form" do
    flow = reduce_flow()

    assert %Jido.Flow.Form.Reduce{initial: %{total: 0}} = flow.forms["total"]
    assert Map.keys(flow.graph.dependencies) == ["total"]
  end

  test "includes collection, initial, and body result references as data dependencies" do
    flow =
      Flow.new!(%{
        name: "reduce_dependencies",
        forms: %{
          items: Accumulate,
          seed: Accumulate,
          extra: Accumulate,
          total: %{
            type: :reduce,
            collection: Ref.result(:items, :values),
            initial: Ref.result(:seed),
            action: Accumulate,
            params: %{
              accumulator: Ref.accumulator(),
              item: Ref.item(),
              extra: Ref.result(:extra)
            }
          }
        },
        output: Ref.result(:total)
      })

    assert {:ok, dependencies} = Flow.dependencies(flow)
    assert dependencies["total"].data == ["extra", "items", "seed"]
  end

  test "keeps accumulator references inside Reduce bodies" do
    assert Ref.select(Ref.accumulator(), :total) == Ref.accumulator(:total)
    assert Ref.select(Ref.item(), :value) == Ref.item(:value)

    assert {:error, step_error} =
             Flow.new(%{
               name: "invalid_accumulator_step",
               forms: %{one: {Accumulate, %{value: Ref.accumulator()}}},
               output: Ref.result(:one)
             })

    assert step_error.details.ref_type == :accumulator
    assert step_error.details.scope == :flow

    assert {:error, map_error} =
             Flow.new(%{
               name: "invalid_accumulator_map",
               forms: %{
                 one: %{
                   type: :map,
                   collection: Ref.input(:values),
                   action: Accumulate,
                   params: %{value: Ref.accumulator()}
                 }
               },
               output: Ref.result(:one)
             })

    assert map_error.details.ref_type == :accumulator
    assert map_error.details.scope == :map
  end

  test "requires an explicit initial value" do
    assert {:error, error} =
             Flow.new(%{
               name: "missing_reduce_initial",
               forms: %{
                 total: %{
                   type: :reduce,
                   collection: Ref.input(:values),
                   action: Accumulate,
                   params: %{accumulator: Ref.accumulator(), item: Ref.item()}
                 }
               },
               output: Ref.result(:total)
             })

    assert error.details.reason == :initial_required
  end

  test "uses collection as the only Reduce collection field" do
    assert {:error, error} =
             Flow.new(%{
               name: "old_reduce_field",
               forms: %{
                 total: %{
                   type: :reduce,
                   over: Ref.input(:values),
                   initial: %{total: 0},
                   action: Accumulate,
                   params: %{accumulator: Ref.accumulator(), item: Ref.item()}
                 }
               },
               output: Ref.result(:total)
             })

    assert error.details.reason == :unknown_field
    assert error.details.field == :over
  end

  test "does not inspect a Reduce target when the Flow is validated" do
    flow =
      Flow.new!(%{
        name: "reduce_flow_body",
        forms: %{
          total: %{
            type: :reduce,
            collection: Ref.input(:values),
            initial: %{total: 0},
            action: MissingReduceAction,
            params: %{accumulator: Ref.accumulator(), item: Ref.item()}
          }
        },
        output: Ref.result(:total)
      })

    assert {:ok, ^flow} = Flow.validate(flow)
  end

  defp reduce_flow do
    Flow.new!(%{
      name: "reduce_values",
      forms: %{
        total: %{
          type: :reduce,
          collection: Ref.input(:values),
          initial: %{total: 0},
          action: Accumulate,
          params: %{
            accumulator: Ref.accumulator(),
            index: Ref.item_index(),
            item: Ref.item()
          },
          timeout_ms: 500,
          retry: [max_attempts: 2]
        }
      },
      output: Ref.result(:total)
    })
  end

  defp registry do
    Registry.new!(%{
      {"actions/accumulate", 1} => {:action, Accumulate},
      {"atoms/accumulator", 1} => {:atom, :accumulator},
      {"atoms/index", 1} => {:atom, :index},
      {"atoms/item", 1} => {:atom, :item},
      {"atoms/total", 1} => {:atom, :total},
      {"atoms/values", 1} => {:atom, :values},
      {"schemas/empty", 1} => {:schema, []}
    })
  end
end
