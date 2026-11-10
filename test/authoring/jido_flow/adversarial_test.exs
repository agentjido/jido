Code.require_file("../support/jido_flow/adversarial.ex", __DIR__)

defmodule Jido.Flow.Authoring.AdversarialTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.{Exec, Flow}
  alias Jido.Flow.{Codec, Ref}
  alias Jido.Test.Flow.Codec, as: Codec
  alias Jido.Test.Flow.Component, as: FlowComponent
  alias Jido.Test.Flow.Authoring.Adversarial.{Echo, Sum}
  @nodes ["load/α", "right.$ref", "left space", "combine"]
  test "unusual names and forward references keep the same result in all authoring forms" do
    input = %{payload: %{"items" => [2]}, right: 3}
    context = %{left: 5}
    expected = %{sum: 10, literal: %{"$ref" => "literal", "$expr" => 7}}

    for {order, index} <- Enum.with_index(permutations(@nodes)) do
      name = "adversarial_order_#{index}"
      module = Module.concat(__MODULE__, "Order#{index}")
      Code.compile_string(source(module, name, order), "authoring_order_#{index}.ex")

      direct =
        Jido.Test.Flow.Builder.new!(
          name: name,
          components: Enum.map(order, &step/1),
          output: output()
        )

      data = %{
        output: output(),
        components: FlowComponent.to_definition(direct.components),
        name: name
      }

      assert {:ok, built} = Jido.Test.Flow.Builder.new(data)
      assert {:ok, document, registry} = Codec.encode(direct)
      assert {:ok, ^document, ^registry} = Codec.encode(direct)

      assert {:ok, restored} =
               Codec.decode(document |> JSON.encode!() |> JSON.decode!(), registry)

      assert module.flow() == direct
      assert built == direct
      assert restored == direct
      assert {:ok, dependencies} = Flow.dependencies(direct)

      assert dependencies["combine"].effective ==
               Enum.sort(["load/α", "right.$ref", "left space"])

      for authored <- [module, direct, built, restored] do
        assert Exec.run(authored, input, context) == {:ok, expected}
      end
    end
  end

  test "three invalid graph mutations fail in source, direct, and stored forms" do
    order = @nodes

    valid =
      Jido.Test.Flow.Builder.new!(
        name: "adversarial_invalid",
        components: Enum.map(order, &step/1),
        output: output()
      )

    assert {:ok, document, registry} = Codec.encode(valid)

    cases = [
      {:duplicate, "duplicate component name", "duplicate Step name", 6},
      {:unknown_need, "Flow reference points to an unknown component", "Flow reference points to an unknown component",
       8},
      {:cycle, "flow dependency graph contains a cycle", "flow dependency graph contains a cycle", 5}
    ]

    for {{kind, expected_message, source_message, source_line}, index} <- Enum.with_index(cases) do
      components = invalid_components(FlowComponent.to_definition(valid.components), kind)

      assert {:error, %{message: ^expected_message}} =
               Jido.Test.Flow.Builder.new(
                 name: valid.name,
                 components: components,
                 output: output()
               )

      data = %{output: output(), components: components, name: valid.name}

      assert {:error, %{message: ^expected_message}} = Jido.Test.Flow.Builder.new(data)

      assert {:error, %{message: ^expected_message}} =
               Codec.decode(invalid_document(document, kind), registry)

      module = Module.concat(__MODULE__, "Invalid#{index}")
      file = "authoring_invalid_#{kind}.ex"

      error =
        assert_raise CompileError, fn ->
          Code.compile_string(source(module, valid.name, order, invalid_declarations(kind)), file)
        end

      assert error.file == file
      assert error.line == source_line
      assert error.description =~ source_message
    end
  end

  test "stored source cannot name an Action outside the trusted registry" do
    flow =
      Jido.Test.Flow.Builder.new!(
        name: "adversarial_storage",
        components: Enum.map(@nodes, &step/1),
        output: output()
      )

    assert {:ok, document, registry} = Codec.encode(flow)
    untrusted = "Elixir.Jido.Test.Flow.Authoring.Untrusted#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(untrusted) end

    changed =
      document
      |> put_in(
        ["components", Access.at(0), "call", "target"],
        %{"id" => untrusted, "vsn" => 1}
      )
      |> JSON.encode!()
      |> JSON.decode!()

    assert {:error,
            %Jido.Error.ValidationError{
              message: "unknown flow catalog reference",
              details: %{
                identifier: ^untrusted,
                path: ["components", 0, "call", "target", "id"]
              }
            }} = Codec.decode(changed, registry)

    assert_raise ArgumentError, fn -> String.to_existing_atom(untrusted) end
  end

  defp output do
    %{sum: Ref.result("combine", :sum), literal: Ref.result("load/α", :literal)}
  end

  defp permutations([]) do
    [[]]
  end

  defp permutations(nodes) do
    for node <- nodes, rest <- permutations(List.delete(nodes, node)) do
      [node | rest]
    end
  end

  defp step("load/α") do
    Jido.Test.Flow.Component.step!(
      name: "load/α",
      action: Echo,
      params: %{
        value: Ref.input([:payload, "items", 0]),
        literal: %{"$ref" => "literal", "$expr" => 7}
      }
    )
  end

  defp step("right.$ref") do
    Jido.Test.Flow.Component.step!(
      name: "right.$ref",
      action: Echo,
      params: %{value: Ref.input(:right)}
    )
  end

  defp step("left space") do
    Jido.Test.Flow.Component.step!(
      name: "left space",
      action: Echo,
      params: %{value: Ref.context(:left)}
    )
  end

  defp step("combine") do
    Jido.Test.Flow.Component.step!(
      name: "combine",
      action: Sum,
      params: %{
        a: Ref.result("load/α", :value),
        b: Ref.result("right.$ref", :value),
        c: Ref.result("left space", :value)
      }
    )
  end

  defp invalid_components(components, :duplicate) do
    duplicate_name = components |> hd() |> Map.fetch!(:name)
    List.update_at(components, 1, &%{&1 | name: duplicate_name})
  end

  defp invalid_components(components, :unknown_need) do
    update_component(components, "combine", &%{&1 | needs: ["absent"]})
  end

  defp invalid_components(components, :cycle) do
    update_component(components, "load/α", &%{&1 | needs: ["combine"]})
  end

  defp invalid_document(document, :duplicate) do
    duplicate_name = get_in(document, ["components", Access.at(0), "name"])
    put_in(document, ["components", Access.at(1), "name"], duplicate_name)
  end

  defp invalid_document(document, :unknown_need) do
    update_document_component(document, "combine", &Map.put(&1, "needs", ["absent"]))
  end

  defp invalid_document(document, :cycle) do
    update_document_component(document, "load/α", &Map.put(&1, "needs", ["combine"]))
  end

  defp update_component(components, name, update) do
    index = Enum.find_index(components, &(&1.name == name))
    List.update_at(components, index, update)
  end

  defp update_document_component(document, name, update) do
    index = Enum.find_index(document["components"], &(&1["name"] == name))
    update_in(document, ["components", Access.at(index)], update)
  end

  defp invalid_declarations(:duplicate) do
    %{"right.$ref" => String.replace(declaration("right.$ref"), "right.$ref", "load/α")}
  end

  defp invalid_declarations(:unknown_need) do
    %{"combine" => declaration("combine") <> ~s|, needs: ["absent"]|}
  end

  defp invalid_declarations(:cycle) do
    %{"load/α" => declaration("load/α") <> ~s|, needs: ["combine"]|}
  end

  defp source(module, name, order, overrides \\ %{}) do
    declarations =
      Enum.map_join(order, "\n", fn step_name ->
        Map.get(overrides, step_name, declaration(step_name))
      end)

    "defmodule #{inspect(module)} do
  use Jido.Flow, name: #{inspect(name)}

  flow do
    #{declarations}
    output(%{sum: result(\"combine\", :sum), literal: result(\"load/α\", :literal)})
  end
end
"
  end

  defp declaration("load/α") do
    ~s|step "load/α", action: #{inspect(Echo)}, params: %{value: input([:payload, "items", 0]), literal: %{"$ref" => "literal", "$expr" => 7}}|
  end

  defp declaration("right.$ref") do
    ~s|step "right.$ref", action: #{inspect(Echo)}, params: %{value: input(:right)}|
  end

  defp declaration("left space") do
    ~s|step "left space", action: #{inspect(Echo)}, params: %{value: context(:left)}|
  end

  defp declaration("combine") do
    ~s|step "combine", action: #{inspect(Sum)}, params: %{a: result("load/α", :value), b: result("right.$ref", :value), c: result("left space", :value)}|
  end
end
