defmodule Jido.Flow.InvokeTest do
  use ExUnit.Case, async: true

  alias Jido.Authoring.Registry
  alias Jido.Flow
  alias Jido.Flow.{Codec, Ref}
  alias Jido.Flow.Form.Invoke

  defmodule Search do
    use Jido.Action, name: "flow_invoke_search"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule Calculate do
    use Jido.Action, name: "flow_invoke_calculate"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule Research do
    use Jido.Flow, name: "flow_invoke_research"

    flow do
      step("search", action: Search, params: %{query: input(:query)})
      output(result("search"))
    end
  end

  defmodule EquivalentResearch do
    use Jido.Flow, name: "flow_invoke_research"

    flow do
      step("search", action: Search, params: %{query: input(:query)})
      output(result("search"))
    end
  end

  defmodule BrokenFlow do
    def __jido_kind__, do: :flow
  end

  defmodule RaisingFlow do
    def __jido_kind__, do: :flow
    def flow, do: raise("Flow construction called child flow/0")
  end

  defmodule Authored do
    use Jido.Flow, name: "flow_invoke_authored"

    flow do
      step("plan",
        action: Search,
        params: %{target: input(:target), arguments: input(:arguments)}
      )

      invoke("tool",
        target: result("plan", :target),
        params: result("plan", :arguments),
        targets: %{"calculate" => Calculate, "research" => Research, "search" => Search},
        on_error: :collect_errors
      )

      output(result("tool"))
    end
  end

  test "DSL, map, and stored JSON produce one canonical Invoke form" do
    from_dsl = Authored.flow()

    from_map =
      Flow.new!(%{
        name: "flow_invoke_authored",
        forms: %{
          "plan" => {Search, %{target: Ref.input(:target), arguments: Ref.input(:arguments)}},
          "tool" => %{
            type: :invoke,
            target: Ref.result("plan", :target),
            params: Ref.result("plan", :arguments),
            targets: %{
              "search" => Search,
              "calculate" => Calculate,
              "research" => Research
            },
            on_error: :collect_errors
          }
        },
        output: Ref.result("tool")
      })

    assert {:ok, document} = Codec.encode_document(from_map, registry())
    assert {:ok, from_json} = Codec.decode_document(document, registry())

    assert {:ok, json} =
             Jido.Authoring.encode_json(from_map, registry: registry(), codec: Codec)

    assert {:ok, from_json_text} =
             Jido.Authoring.decode_json(json, registry: registry(), codec: Codec)

    assert from_dsl == from_map
    assert from_json == from_map
    assert from_json_text == from_map
    assert %Invoke{} = from_map.forms["tool"]
    assert Flow.semantic_identity(from_dsl) == Flow.semantic_identity(from_json)
    assert document["forms"] |> Enum.at(1) |> Enum.at(1) |> Map.fetch!("type") == "invoke"
  end

  test "candidate data is semantic and metadata is not semantic" do
    build = fn targets, trace ->
      Flow.new!(%{
        name: "invoke_identity",
        forms: %{
          tool: %{
            type: :invoke,
            target: "search",
            targets: targets,
            meta: %{trace: trace}
          }
        },
        output: Ref.result(:tool)
      })
    end

    first = build.(%{"search" => Search}, "one")
    same = build.(%{"search" => Search}, "two")
    changed = build.(%{"calculate" => Calculate, "search" => Search}, "one")

    assert Flow.semantic_identity(first) == Flow.semantic_identity(same)
    refute Flow.semantic_identity(first) == Flow.semantic_identity(changed)

    research = build.(%{"research" => Research}, "one")
    equivalent_research = build.(%{"research" => EquivalentResearch}, "one")
    refute Flow.semantic_identity(research) == Flow.semantic_identity(equivalent_research)
  end

  test "candidate identity uses the target module without calling child flow/0" do
    assert {:ok, flow} = invoke_flow(%{"raising" => RaisingFlow})
    assert flow.forms["tool"].targets == %{"raising" => RaisingFlow}
    assert {:ok, flow.identity} == Flow.semantic_identity(flow)
  end

  test "target and params references create data dependencies" do
    flow =
      Flow.new!(%{
        name: "invoke_dependencies",
        forms: %{
          plan: Search,
          arguments: Search,
          tool: %{
            type: :invoke,
            target: Ref.result(:plan, :target),
            params: Ref.result(:arguments),
            targets: %{"search" => Search}
          }
        },
        output: Ref.result(:tool)
      })

    assert {:ok, dependencies} = Flow.dependencies(flow)
    assert dependencies["tool"].data == ["arguments", "plan"]
  end

  test "Invoke stays one dynamic call and does not expand the graph" do
    flow =
      Flow.new!(%{
        name: "invoke_program",
        forms: %{
          tool: %{
            type: :invoke,
            target: Ref.input(:target),
            targets: %{"calculate" => Calculate, "search" => Search}
          }
        },
        output: Ref.result(:tool)
      })

    assert %Invoke{} = flow.forms["tool"]
    assert Map.keys(flow.graph.dependencies) == ["tool"]
  end

  test "rejects empty, invalid, and duplicate stored candidates" do
    assert {:error, error} = invoke_flow(%{})
    assert error.details.reason == :empty_invoke_targets

    assert {:error, error} = invoke_flow(%{"" => Search})
    assert error.details.reason == :invalid_invoke_target_id

    assert {:error, error} = invoke_flow(%{:search => Search})
    assert error.details.reason == :invalid_invoke_target_id

    flow = invoke_flow!(%{"search" => Search})
    assert {:ok, document} = Codec.encode_document(flow, registry())
    [id, form, needs] = hd(document["forms"])
    [candidate] = form["targets"]
    duplicate = %{form | "targets" => [candidate, candidate]}

    assert {:error, [issue]} =
             Codec.decode_document(%{document | "forms" => [[id, duplicate, needs]]}, registry())

    assert issue.details.reason == :duplicate_invoke_target
  end

  test "rejects unknown candidates and policies that can select a Flow" do
    assert {:error, error} = invoke_flow(%{"unknown" => String})
    assert error.details.reason == :invalid_invoke_candidate

    assert {:error, error} = invoke_flow(%{"broken" => BrokenFlow})
    assert error.details.reason == :invalid_invoke_candidate

    assert {:error, error} =
             Flow.new(%{
               name: "invoke_flow_policy",
               forms: %{
                 tool: %{
                   type: :invoke,
                   target: "research",
                   targets: %{"research" => Research, "search" => Search},
                   timeout_ms: 100
                 }
               },
               output: Ref.result(:tool)
             })

    assert error.details.reason == :unsupported_flow_call_policy
  end

  test "Codec rejects unknown fields and unregistered candidates" do
    flow = invoke_flow!(%{"search" => Search})
    assert {:ok, document} = Codec.encode_document(flow, registry())
    [id, form, needs] = hd(document["forms"])

    assert {:error, [issue]} =
             Codec.decode_document(
               %{document | "forms" => [[id, Map.put(form, "extra", true), needs]]},
               registry()
             )

    assert issue.path == ["forms", 0, 1, "extra"]

    assert {:error, _error} = Codec.encode_document(flow, registry_without_actions())
  end

  defp invoke_flow(targets) do
    Flow.new(%{
      name: "invoke_validation",
      forms: %{tool: %{type: :invoke, target: "search", targets: targets}},
      output: Ref.result(:tool)
    })
  end

  defp invoke_flow!(targets) do
    {:ok, flow} = invoke_flow(targets)
    flow
  end

  defp registry do
    Registry.new!(%{
      {"actions/search", 1} => {:action, Search},
      {"actions/calculate", 1} => {:action, Calculate},
      {"flows/research", 1} => {:flow, Research},
      {"atoms/target", 1} => {:atom, :target},
      {"atoms/arguments", 1} => {:atom, :arguments},
      {"schemas/empty", 1} => {:schema, []}
    })
  end

  defp registry_without_actions do
    Registry.new!(%{{"schemas/empty", 1} => {:schema, []}})
  end
end
