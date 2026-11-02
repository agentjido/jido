defmodule Jido.Flow.ChoiceTest do
  use ExUnit.Case, async: true

  alias Jido.Authoring.Registry
  alias Jido.Flow
  alias Jido.Flow.{Codec, Ref}

  defmodule Echo do
    use Jido.Action, name: "flow_choice_echo"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule Authored do
    use Jido.Flow, name: "choose_route"

    flow do
      choice "route" do
        option("large",
          condition: input(:value) > 10,
          action: Echo,
          params: %{route: "large"},
          timeout_ms: 500,
          retry: [max_attempts: 2]
        )

        otherwise(action: Echo, params: %{route: "small"})
      end

      output(result("route"))
    end
  end

  test "normalizes ordered Choice options and one fallback" do
    flow =
      Flow.new!(%{
        name: "choose_route",
        forms: %{
          route: %{
            type: :choice,
            options: [
              {"large", Jido.Expr.new!(:>, [Ref.input(:value), 10]), {Echo, %{route: "large"}}}
            ],
            fallback: {Echo, %{route: "small"}}
          }
        },
        output: Ref.result(:route)
      })

    assert flow.forms["route"].__struct__ == Jido.Flow.Form.Choice
  end

  test "DSL, map, and JSON authoring produce the same canonical Choice form" do
    from_dsl = Authored.flow()
    from_map = choice_flow()
    registry = registry()

    assert {:ok, document} = Codec.encode_document(from_map, registry)
    assert {:ok, from_json} = Codec.decode_document(document, registry)

    assert from_dsl == from_map
    assert from_json == from_map
    assert [{"large", _condition, call}] = from_map.forms["route"].options
    assert call.policy.retry.max_attempts == 2
    assert get_in(document, ["forms", Access.at(0), Access.at(1), "type"]) == "choice"
  end

  test "keeps Choice branches inside one named graph form" do
    flow = choice_flow()

    assert %Jido.Flow.Form.Choice{} = flow.forms["route"]
    assert Map.keys(flow.graph.dependencies) == ["route"]
    assert flow.graph.dependencies["route"] == %{data: [], control: []}
  end

  test "includes condition and target references as data dependencies" do
    flow =
      Flow.new!(%{
        name: "choice_dependencies",
        forms: %{
          flag: Echo,
          selected: Echo,
          fallback: Echo,
          route: %{
            type: :choice,
            options: [
              {"selected", Ref.result(:flag, :enabled), {Echo, %{value: Ref.result(:selected)}}}
            ],
            fallback: {Echo, %{value: Ref.result(:fallback)}}
          }
        },
        output: Ref.result(:route)
      })

    assert {:ok, dependencies} = Flow.dependencies(flow)
    assert dependencies["route"].data == ["fallback", "flag", "selected"]
  end

  test "requires Boolean-compatible conditions, unique names, and a fallback" do
    assert {:error, condition_error} =
             Flow.new(%{
               name: "invalid_choice_condition",
               forms: %{
                 route: %{
                   type: :choice,
                   options: [{"bad", 123, Echo}],
                   fallback: Echo
                 }
               },
               output: Ref.result(:route)
             })

    assert condition_error.details.path == [:forms, "route", :options, 0]

    assert {:error, duplicate_error} =
             Flow.new(%{
               name: "duplicate_choice_options",
               forms: %{
                 route: %{
                   type: :choice,
                   options: [{"same", true, Echo}, {:same, false, Echo}],
                   fallback: Echo
                 }
               },
               output: Ref.result(:route)
             })

    assert duplicate_error.details.reason == :duplicate_option

    assert {:error, fallback_error} =
             Flow.new(%{
               name: "missing_choice_fallback",
               forms: %{
                 route: %{type: :choice, options: [{"one", true, Echo}]}
               },
               output: Ref.result(:route)
             })

    assert fallback_error.details.reason == :fallback_required
  end

  defp choice_flow do
    Flow.new!(%{
      name: "choose_route",
      forms: %{
        route: %{
          type: :choice,
          options: [
            {"large", condition(),
             %{
               type: :call,
               action: Echo,
               params: %{route: "large"},
               timeout_ms: 500,
               retry: [max_attempts: 2]
             }}
          ],
          fallback: {Echo, %{route: "small"}}
        }
      },
      output: Ref.result(:route)
    })
  end

  defp condition, do: Jido.Expr.new!(:>, [Ref.input(:value), 10])

  defp registry do
    Registry.new!(%{
      {"actions/echo", 1} => {:action, Echo},
      {"atoms/route", 1} => {:atom, :route},
      {"atoms/value", 1} => {:atom, :value},
      {"schemas/empty", 1} => {:schema, []}
    })
  end
end
