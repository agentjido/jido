defmodule Jido.Flow.ParallelTest do
  use ExUnit.Case, async: true

  alias Jido.Authoring.Registry
  alias Jido.Flow
  alias Jido.Flow.{Codec, Ref}

  defmodule Echo do
    use Jido.Action, name: "flow_parallel_echo"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule Authored do
    use Jido.Flow, name: "parallel_checks"

    flow do
      step("load", action: Echo, params: %{value: input(:value)})

      parallel "checks", on_error: :collect_errors do
        action("input", Echo,
          params: %{value: result("load", :value)},
          timeout_ms: 500,
          retry: [max_attempts: 2]
        )

        action("mode", Echo, params: %{value: input(:mode)})
      end

      output(result("checks"))
    end
  end

  test "normalizes one ordered Parallel form" do
    flow = parallel_flow()

    assert %Jido.Flow.Form.Parallel{
             actions: [
               {"input", %Jido.Flow.Call{instruction: %Jido.Instruction{target: Echo}}},
               {"mode", %Jido.Flow.Call{instruction: %Jido.Instruction{target: Echo}}}
             ],
             on_error: :collect_errors
           } = flow.forms["checks"]
  end

  test "DSL, map, and JSON authoring produce the same canonical Parallel form" do
    from_dsl = Authored.flow()
    from_map = parallel_flow()
    registry = registry()

    assert {:ok, document} = Codec.encode_document(from_map, registry)
    assert {:ok, from_json} = Codec.decode_document(document, registry)

    assert from_dsl == from_map
    assert from_json == from_map
    assert [{"input", input_call}, {"mode", _mode_call}] = from_map.forms["checks"].actions
    assert input_call.policy.retry.max_attempts == 2

    assert Enum.any?(document["forms"], fn
             ["checks", %{"type" => "parallel"}, []] -> true
             _form -> false
           end)
  end

  test "keeps Parallel branches inside one named graph form" do
    flow = parallel_flow()

    assert Map.keys(flow.graph.dependencies) == ["checks", "load"]
    assert flow.graph.dependencies["checks"] == %{data: ["load"], control: []}
  end

  test "includes every Action reference as a data dependency" do
    assert {:ok, dependencies} = Flow.dependencies(parallel_flow())
    assert dependencies["checks"].data == ["load"]
  end

  test "adds branch references to the named Parallel form" do
    flow =
      Flow.new!(%{
        name: "parallel_dependency_routes",
        forms: %{
          first: Echo,
          second: Echo,
          checks: %{
            type: :parallel,
            actions: [
              {"first", {Echo, %{value: Ref.result(:first)}}},
              {"second", {Echo, %{value: Ref.result(:second)}}}
            ]
          }
        },
        output: Ref.result(:checks)
      })

    assert flow.graph.dependencies["checks"] == %{
             data: ["first", "second"],
             control: []
           }
  end

  test "adds one control dependency to the named Parallel form" do
    flow =
      Flow.new!(%{
        name: "parallel_control_route",
        forms: %{
          gate: Echo,
          checks: %{
            type: :parallel,
            actions: [
              {"first", {Echo, %{value: Ref.input(:first)}}},
              {"second", {Echo, %{value: Ref.input(:second)}}}
            ]
          }
        },
        needs: %{checks: [:gate]},
        output: Ref.result(:checks)
      })

    assert flow.graph.dependencies["checks"] == %{data: [], control: ["gate"]}
  end

  test "requires actions, unique names, and a valid error policy" do
    assert {:error, empty} =
             Flow.new(%{
               name: "empty_parallel",
               forms: %{checks: %{type: :parallel, actions: []}},
               output: Ref.result(:checks)
             })

    assert empty.details.reason == :empty_actions

    assert {:error, duplicate} =
             Flow.new(%{
               name: "duplicate_parallel",
               forms: %{
                 checks: %{
                   type: :parallel,
                   actions: [{"same", Echo}, {:same, Echo}]
                 }
               },
               output: Ref.result(:checks)
             })

    assert duplicate.details.reason == :duplicate_action

    assert {:error, policy} =
             Flow.new(%{
               name: "invalid_parallel_policy",
               forms: %{
                 checks: %{
                   type: :parallel,
                   actions: [{"one", Echo}],
                   on_error: :ignore
                 }
               },
               output: Ref.result(:checks)
             })

    assert policy.details.reason == :on_error
  end

  test "does not inspect Parallel targets when the Flow is validated" do
    flow =
      Flow.new!(%{
        name: "parallel_flow_target",
        forms: %{
          checks: %{
            type: :parallel,
            actions: [{"missing", MissingParallelAction}]
          }
        },
        output: Ref.result(:checks)
      })

    assert {:ok, ^flow} = Flow.validate(flow)
  end

  defp parallel_flow do
    Flow.new!(%{
      name: "parallel_checks",
      forms: %{
        load: {Echo, %{value: Ref.input(:value)}},
        checks: %{
          type: :parallel,
          actions: [
            {"input",
             %{
               type: :call,
               action: Echo,
               params: %{value: Ref.result(:load, :value)},
               timeout_ms: 500,
               retry: [max_attempts: 2]
             }},
            {"mode", {Echo, %{value: Ref.input(:mode)}}}
          ],
          on_error: :collect_errors
        }
      },
      output: Ref.result(:checks)
    })
  end

  defp registry do
    Registry.new!(%{
      {"actions/echo", 1} => {:action, Echo},
      {"atoms/mode", 1} => {:atom, :mode},
      {"atoms/value", 1} => {:atom, :value},
      {"schemas/empty", 1} => {:schema, []}
    })
  end
end
