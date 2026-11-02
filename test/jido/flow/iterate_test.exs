defmodule Jido.Flow.IterateTest do
  use ExUnit.Case, async: true

  alias Jido.Authoring.Registry
  alias Jido.Flow
  alias Jido.Flow.{Call, Codec, Ref}

  defmodule Tick do
    use Jido.Action, name: "flow_iterate_tick"

    @impl true
    def run(%{state: state}, _context), do: {:ok, %{count: state.count + 1}}
  end

  defmodule Authored do
    use Jido.Flow, name: "iterate_until_done"

    flow do
      iterate "work" do
        state([], initial: %{count: input(:start)})
        action(Tick)
        params(%{state: state(), index: iteration_index()})
        update(body_result())
        while(state(:count) < 3)
        max_iterations(10)
        timeout_ms(500)
        retry(max_attempts: 2)
      end

      output(result("work"))
    end
  end

  test "DSL, map, and JSON authoring produce the same canonical Iterate form" do
    from_dsl = Authored.flow()
    from_map = iterate_flow()
    registry = registry()

    assert {:ok, document} = Codec.encode_document(from_map, registry)
    assert {:ok, from_json} = Codec.decode_document(document, registry)

    assert from_dsl == from_map
    assert from_json == from_map
    assert from_map.forms["work"].call.policy.retry.max_attempts == 2
    assert get_in(document, ["forms", Access.at(0), Access.at(1), "type"]) == "iterate"
  end

  test "keeps Iterate state inside one named graph form" do
    flow = iterate_flow()

    assert %Jido.Flow.Form.Iterate{
             mode: {:while, condition, 10},
             state_schema: [],
             initial: initial,
             call: %Call{instruction: instruction},
             update: %Ref{source: :body_result}
           } = flow.forms["work"]

    assert condition == Jido.Expr.new!(:<, [Ref.state(:count), 3])
    assert initial == %{count: Ref.input(:start)}
    assert instruction.target == Tick
    assert instruction.params == %{state: Ref.state(), index: Ref.iteration_index()}
    assert Map.keys(flow.graph.dependencies) == ["work"]
  end

  test "normalizes fixed repeat as the second bounded Iterate mode" do
    flow =
      Flow.new!(%{
        name: "repeat_work",
        forms: %{
          work: %{
            type: :iterate,
            state_schema: [],
            initial: %{count: 0},
            repeat: 3,
            action: Tick,
            params: %{state: Ref.state()},
            update: Ref.body_result()
          }
        },
        output: Ref.result(:work)
      })

    assert %Jido.Flow.Form.Iterate{
             mode: {:repeat, 3},
             state_schema: [],
             initial: %{count: 0},
             call: %Call{},
             update: %Ref{}
           } = flow.forms["work"]
  end

  test "includes initial, condition, body, and update result references as dependencies" do
    flow =
      Flow.new!(%{
        name: "iterate_dependencies",
        forms: %{
          seed: Tick,
          bound: Tick,
          extra: Tick,
          finish: Tick,
          work: %{
            type: :iterate,
            state_schema: [],
            initial: Ref.result(:seed),
            while: Ref.result(:bound, :continue),
            max_iterations: 10,
            action: Tick,
            params: %{state: Ref.state(), extra: Ref.result(:extra)},
            update: %{state: Ref.body_result(), finish: Ref.result(:finish)}
          }
        },
        output: Ref.result(:work)
      })

    assert {:ok, dependencies} = Flow.dependencies(flow)
    assert dependencies["work"].data == ["bound", "extra", "finish", "seed"]
  end

  test "keeps Iterate references inside their valid phases" do
    assert {:error, step_error} =
             Flow.new(%{
               name: "state_outside_iterate",
               forms: %{work: {Tick, %{state: Ref.state()}}},
               output: Ref.result(:work)
             })

    assert step_error.details.ref_type == :state
    assert step_error.details.scope == :flow

    assert {:error, params_error} =
             Flow.new(%{
               name: "body_result_before_body",
               forms: %{
                 work: %{
                   type: :iterate,
                   state_schema: [],
                   initial: %{},
                   repeat: 1,
                   action: Tick,
                   params: %{value: Ref.body_result()}
                 }
               },
               output: Ref.result(:work)
             })

    assert params_error.details.ref_type == :body_result
    assert params_error.details.scope == :iterate_params
  end

  test "requires one bounded mode" do
    attrs = %{
      name: "unbounded_iterate",
      forms: %{
        work: %{
          type: :iterate,
          state_schema: [],
          initial: %{},
          action: Tick,
          params: %{state: Ref.state()}
        }
      },
      output: Ref.result(:work)
    }

    assert {:error, error} = Flow.new(attrs)
    assert error.details.reason == :mode
  end

  defp iterate_flow do
    Flow.new!(%{
      name: "iterate_until_done",
      forms: %{
        work: %{
          type: :iterate,
          state_schema: [],
          initial: %{count: Ref.input(:start)},
          while: Jido.Expr.new!(:<, [Ref.state(:count), 3]),
          max_iterations: 10,
          action: Tick,
          params: %{state: Ref.state(), index: Ref.iteration_index()},
          update: Ref.body_result(),
          timeout_ms: 500,
          retry: [max_attempts: 2]
        }
      },
      output: Ref.result(:work)
    })
  end

  defp registry do
    Registry.new!(%{
      {"actions/tick", 1} => {:action, Tick},
      {"atoms/count", 1} => {:atom, :count},
      {"atoms/index", 1} => {:atom, :index},
      {"atoms/start", 1} => {:atom, :start},
      {"atoms/state", 1} => {:atom, :state},
      {"schemas/empty", 1} => {:schema, []}
    })
  end
end
