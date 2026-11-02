defmodule Jido.Flow.CodecTest do
  use ExUnit.Case, async: true

  alias Jido.Authoring.Registry
  alias Jido.Flow
  alias Jido.Flow.{Codec, Ref}
  alias Jido.Flow.Codec.{Limits, Value}

  defmodule Echo do
    use Jido.Action, name: "codec_echo"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  test "stores the canonical definition and rebuilds the graph later" do
    flow =
      Flow.new!(%{
        name: "stored",
        forms: %{
          first: {Echo, %{value: 1}},
          second: {Echo, %{value: Ref.result(:first)}}
        },
        output: Ref.result(:second)
      })

    registry = registry()

    assert {:ok, document} = Codec.encode_document(flow, registry)
    refute Map.has_key?(document, "vsn")
    assert is_list(document["forms"])
    refute Map.has_key?(document, "graph")
    refute Map.has_key?(document, "identity")
    refute Map.has_key?(get_in(document, ["forms", Access.at(0), Access.at(1)]), "vsn")
    assert get_in(document, ["forms", Access.at(0), Access.at(1), "type"]) == "call"

    assert {:ok, restored} = Codec.decode_document(document, registry)
    assert restored == flow
    assert Flow.semantic_identity(restored) == Flow.semantic_identity(flow)
    assert restored.graph == flow.graph
    assert restored.identity == flow.identity
  end

  test "rejects version fields" do
    flow = Flow.new!(%{name: "stored", forms: %{echo: Echo}, output: Ref.result(:echo)})
    registry = registry()

    assert {:ok, document} = Codec.encode_document(flow, registry)

    assert {:error, [%Jido.Authoring.Issue{path: ["vsn"]}]} =
             Codec.decode_document(Map.put(document, "vsn", 1), registry)

    [id, form, needs] = hd(document["forms"])
    document = %{document | "forms" => [[id, Map.put(form, "vsn", 1), needs]]}

    assert {:error, [%Jido.Authoring.Issue{path: ["forms", 0, 1, "vsn"]}]} =
             Codec.decode_document(document, registry)
  end

  test "stores result references with Step vocabulary" do
    registry = registry()

    assert {:ok,
            %{
              "$ref" => %{
                "source" => "result",
                "step" => "first",
                "path" => ["value"]
              }
            } = stored} =
             Jido.Flow.Codec.Value.encode_expression(
               Ref.result(:first, "value"),
               registry,
               0
             )

    refute get_in(stored, ["$ref", "component"])

    assert {:ok, %Ref{source: :result, step: "first", path: ["value"]}} =
             Jido.Flow.Codec.Value.decode(stored, registry, ["value"])
  end

  test "round trips mixed literal, reference, and expression values" do
    value = %{
      "condition" => Jido.Expr.new!(:<, [Ref.input(:mode), 10]),
      7 => [Ref.result(:first, "value"), :value]
    }

    assert {:ok, stored} = Value.encode_expression(value, registry(), 0)
    assert {:ok, ^value} = Value.decode(stored, registry(), ["value"])

    assert %{"$type" => "map", "entries" => entries} = stored
    assert length(entries) == 2
  end

  test "returns all local errors for a malformed stored expression" do
    stored = %{
      "$expr" => %{
        "operator" => "unknown",
        "operands" => :not_a_list,
        "extra" => true
      },
      "extra" => true
    }

    assert {:error, errors} = Value.decode(stored, registry(), ["root"])

    assert MapSet.new(Enum.map(errors, & &1.details.path)) ==
             MapSet.new([
               ["root", "extra"],
               ["root", "$expr", "extra"],
               ["root", "$expr", "operator"],
               ["root", "$expr", "operands"]
             ])
  end

  test "rejects duplicate stored map keys and expression tags in data mode" do
    stored_map = %{
      "$type" => "map",
      "entries" => [
        %{"key" => "same", "value" => 1},
        %{"key" => "same", "value" => 2}
      ]
    }

    assert {:error, [duplicate]} = Value.decode(stored_map, registry(), ["map"])
    assert duplicate.details.path == ["map", "entries", 1, "key"]

    stored_ref = %{
      "$ref" => %{"source" => "input", "step" => nil, "path" => []}
    }

    assert {:error, [invalid]} = Value.decode(stored_ref, registry(), ["data"], :data)
    assert invalid.details.path == ["data"]
  end

  test "applies stored collection, nesting, and proper-list limits" do
    assert {:error, size_error} = Limits.size(List.duplicate(0, 10_001))
    assert size_error.details.maximum_size == 10_000

    nested = Enum.reduce(1..102, 0, fn _index, value -> [value] end)
    assert {:error, [depth_error]} = Value.decode(nested, registry(), ["nested"])
    assert depth_error.details.maximum_depth == 100

    assert {:error, list_error} = Limits.check([1 | :tail])
    assert list_error.message == "stored Flow data must contain proper lists"
  end

  test "translates portable value failures into Flow errors" do
    registry = registry()

    cases = [
      {<<255>>, "flow data strings must be valid UTF-8"},
      {[1 | :tail], "flow data must contain proper lists"},
      {%{-1 => :value}, "flow data contains an unsupported map key"},
      {{:tuple}, "flow data contains an unsupported value"},
      {Enum.reduce(1..102, 0, fn _index, value -> [value] end),
       "stored Flow exceeds its nesting limit"},
      {List.duplicate(0, 10_001), "stored Flow collection exceeds its size limit"}
    ]

    for {value, message} <- cases do
      assert {:error, error} = Value.encode_data(value, registry, 0)
      assert error.message == message
    end

    assert {:error, registry_error} = Value.encode_data(:unregistered, registry, 0)
    assert registry_error.message =~ "flow registry"
  end

  test "reports malformed tagged values at their stored paths" do
    registry = registry()

    malformed = [
      {%{"$type" => "map", "entries" => :invalid}, ["root", "entries"]},
      {%{"$type" => "map", "entries" => [%{"key" => -1, "value" => 1}]},
       ["root", "entries", 0, "key"]},
      {%{"$type" => "map", "entries" => [:invalid]}, ["root", "entries", 0]},
      {%{"$ref" => %{"source" => "unknown", "step" => 1, "path" => []}},
       ["root", "$ref", "source"]},
      {%{"$ref" => %{"source" => "input", "step" => nil, "path" => :invalid}},
       ["root", "$ref", "path"]},
      {%{"$expr" => %{"operator" => "<", "operands" => [%{"bad" => true}]}},
       ["root", "$expr", "operands", 0]}
    ]

    for {stored, path} <- malformed do
      assert {:error, errors} = Value.decode(stored, registry, ["root"])
      assert Enum.any?(errors, &(&1.details.path == path))
    end

    atom_with_extra = %{
      "$type" => "atom",
      "id" => "atoms/value",
      "vsn" => 1,
      "extra" => true
    }

    assert {:error, [extra]} = Value.decode(atom_with_extra, registry, ["root"])
    assert extra.details.path == ["root", "extra"]
  end

  defp registry do
    Registry.new!(%{
      {"actions/echo", 1} => {:action, Echo},
      {"atoms/value", 1} => {:atom, :value},
      {"atoms/mode", 1} => {:atom, :mode},
      {"schemas/empty", 1} => {:schema, []}
    })
  end
end
