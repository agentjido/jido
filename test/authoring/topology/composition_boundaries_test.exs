Code.require_file("../support/topology/corpus.exs", __DIR__)

defmodule JidoTest.Authoring.Topology.CompositionBoundariesTest do
  use ExUnit.Case, async: false
  @moduletag :authoring

  alias Jido.Error.ValidationError
  alias Jido.Topology
  alias Jido.Topology.{Builder, Codec, Plan, Ref}
  alias JidoTest.Authoring.Topology.Corpus

  setup %{variant: variant} do
    Corpus.load!(variant)
    {:ok, spec: Corpus.spec(variant)}
  end

  @tag variant: :repeated
  test "component order cannot change scoped identities, inputs, or the shared Bus", %{spec: spec} do
    expected = hd(spec.scenarios).plan

    for form <- Corpus.forms() do
      definition = Corpus.definition(spec, form)
      reversed = %{definition | includes: Enum.reverse(definition.includes)}
      assert {:ok, instance} = Topology.instantiate(reversed, id: "corpus")
      assert instance.plan === expected
    end

    document = Map.update!(spec.document, "includes", &Enum.reverse/1)
    assert {:ok, decoded} = Codec.decode(document, spec.registry, id: "corpus")
    assert decoded.plan === expected

    assert Plan.resolve(expected, Ref.ref("team/a", :public_worker), :agent) ==
             "component/team%2Fa/agent/worker"

    assert Plan.resolve(expected, Ref.ref("team%2Fa", :public_worker), :agent) ==
             "component/team%252Fa/agent/worker"

    assert Plan.resolve(expected, Ref.ref("team/a", :worker), :agent) == nil
  end

  @tag variant: :repeated
  test "ownership cycles across sibling exports fail in Builders and stored JSON", %{spec: spec} do
    left = Ref.ref("team/a", :public_worker)
    right = Ref.ref("team%2Fa", :public_worker)
    base = Corpus.builder(spec)

    assert {:error, %ValidationError{message: message}} =
             base |> Builder.owns(left, right) |> Builder.owns(right, left) |> Builder.build()

    assert message =~ "contains a cycle"

    ref = fn component ->
      %{"$type" => "topology.ref", "component" => component, "key" => "public_worker"}
    end

    document =
      Map.put(spec.document, "relationships", [
        %{"parent" => ref.("team/a"), "child" => ref.("team%2Fa"), "on_parent_exit" => "stop"},
        %{"parent" => ref.("team%2Fa"), "child" => ref.("team/a"), "on_parent_exit" => "stop"}
      ])

    assert {:error, %ValidationError{message: ^message}} = Codec.decode(document, spec.registry)
    assert {:ok, valid} = Builder.build(base, id: "corpus")
    assert valid.plan === hd(spec.scenarios).plan
  end

  @tag variant: :deep
  test "re-exported endpoints retain kinds and hide deeper paths", %{spec: spec} do
    assert {:ok, instance} = Codec.decode(spec.document, spec.registry, id: "corpus")
    plan = instance.plan
    prefix = "component/region/component/team/"
    assert Plan.resolve(plan, Ref.ref(:region, :leader), :agent) == prefix <> "agent/leader"

    assert Plan.resolve(plan, Ref.ref(:region, :workers), :agent, 2) ==
             prefix <> "group/workers/2"

    assert Plan.resolve(plan, Ref.ref(:region, :events), :bus) == "bus/events"
    assert Plan.resolve(plan, Ref.ref(:region, :leader), :bus) == nil
    # Resolution returns a stable key; membership is a separate plan lookup.
    missing = Plan.resolve(plan, Ref.ref(:region, :workers), :agent, 3)
    assert missing == prefix <> "group/workers/3"
    refute Map.has_key?(plan.agents, missing)
    assert Plan.resolve(plan, Ref.ref("region/team", :leader), :agent) == nil
    assert Plan.resolve(plan, prefix <> "agent/leader", :agent) == nil
  end

  @tag variant: :deep
  test "nested binding and export failures retain their error details after transport", %{
    spec: spec
  } do
    path = ["includes", Access.at(0), "topology", "includes", Access.at(0)]
    child = get_in(spec.document, path)

    for bindings <- [[], child["bindings"] ++ [%{"key" => "extra", "to" => "events"}]] do
      document = put_in(spec.document, path ++ ["bindings"], bindings)

      assert {:error, %ValidationError{message: message, details: details}} =
               Codec.decode(document, spec.registry)

      assert message == "Import bindings must match the child requirements"

      assert details == %{
               path: ["region", "team"],
               required: ["events"],
               supplied: Enum.sort(Enum.map(bindings, & &1["key"]))
             }
    end

    duplicate =
      put_in(spec.document, path ++ ["bindings"], child["bindings"] ++ child["bindings"])

    assert {:error, %ValidationError{message: "Duplicate import binding"}} =
             Codec.decode(duplicate, spec.registry)

    wrong_kind =
      put_in(spec.document, path ++ ["topology", "exports", Access.at(0), "kind"], "bus")

    assert {:error, %ValidationError{details: %{expected: [:bus], actual: :agent}}} =
             Codec.decode(wrong_kind, spec.registry)

    private =
      put_in(spec.document, ["agents", Access.at(0), "depends_on"], [
        %{"$type" => "topology.ref", "component" => "region/team", "key" => "leader"}
      ])

    assert {:error,
            %ValidationError{
              message: "Unknown included topology",
              details: %{path: ["region/team"]}
            }} =
             Codec.decode(private, spec.registry)

    assert {:ok, valid} = Codec.decode(spec.document, spec.registry, id: "corpus")
    assert valid.plan === hd(spec.scenarios).plan
  end

  @tag variant: :deep
  test "invalid child input is a planning failure with both component paths", %{spec: spec} do
    for form <- Corpus.forms() do
      definition = Corpus.definition(spec, form)

      path = [
        Access.key(:includes),
        Access.at(0),
        Access.key(:topology),
        Access.key(:includes),
        Access.at(0),
        Access.key(:inputs),
        Access.key(:count)
      ]

      invalid = put_in(definition, path, "not a count")

      # Static declarations are still valid; only the child's input is invalid.
      assert {:ok, ^invalid} = Topology.new(invalid)
      assert {:ok, document} = Codec.encode(invalid, spec.registry)
      assert {:ok, ^invalid} = Codec.decode(document, spec.registry)

      for result <- [
            Topology.instantiate(invalid, id: "corpus"),
            Builder.build(Builder.new(invalid), id: "corpus"),
            Codec.decode(document, spec.registry, id: "corpus")
          ] do
        assert {:error,
                %ValidationError{message: "Invalid included topology input", details: details}} =
                 result

        assert details.path == ["region"]

        assert %ValidationError{
                 message: "Invalid included topology input",
                 details: child_details
               } = details.cause

        assert child_details.path == ["region", "team"]
        assert %ValidationError{message: "Invalid topology input"} = child_details.cause
      end

      assert {:ok, recovered} = Topology.instantiate(definition, id: "corpus")
      assert recovered.plan === hd(spec.scenarios).plan
    end
  end

  @tag variant: :deep
  test "the child limit rejects expansion even when the root still has room", %{spec: spec} do
    assert {:ok, definition} = Codec.decode(spec.document, spec.registry)
    assert definition.startup.max_agents == 5

    assert {:error, %ValidationError{message: "Topology exceeds startup.max_agents"}} =
             Topology.instantiate(definition, id: "corpus", input: %{count: 3})

    # Three workers plus the leader hit a child limit of three, not the root's five.
    assert {:ok, valid} = Topology.instantiate(definition, id: "corpus")
    assert valid.plan.components[["region", "team"]].agents == 3
    assert valid.plan === hd(spec.scenarios).plan
  end
end
