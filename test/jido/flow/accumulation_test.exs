defmodule Jido.Flow.AccumulationTest do
  use ExUnit.Case, async: true

  alias Jido.Authoring.Registry
  alias Jido.Flow.{Codec, Definition, Error}
  alias JidoActionTest.FlowCodec, as: Codec

  defp document do
    registry =
      Registry.new!(%{
        {"action", 1} => {:action, UnloadedAction},
        {"schema", 1} => {:schema, Zoi.map()}
      })

    flow =
      JidoActionTest.FlowBuilder.new!(
        name: "ordered",
        components: [JidoActionTest.FlowComponent.step!(name: "one", action: UnloadedAction)],
        output: %{}
      )

    {:ok, document} = Codec.encode(flow, registry)
    {document, registry}
  end

  test "needs names preserve normalized order and error precedence" do
    names = ["last", :first] ++ Enum.map(1..128, &"name_#{&1}")
    assert {:ok, normalized} = normalize_needs(names)
    assert normalized == Enum.map(names, &to_string/1)

    assert {:error, %{message: "component needs contains a duplicate", details: %{name: "first"}}} =
             normalize_needs([:first, "last", "first", "last"])

    assert {:error, %{message: "component needs must contain component names"}} =
             normalize_needs([:first, "first", nil])

    assert {:error, %{message: "component needs must be a proper list"}} =
             normalize_needs(["first" | :tail])

    assert {:error, %{message: "component needs must be a list"}} =
             normalize_needs("first")
  end

  test "needs validation has bounded reduction growth" do
    # Eight times the input permits twice the linear growth. This checks BEAM
    # work, not wall time, and catches repeated copies of the accumulated list.
    counts =
      for size <- [2048, 16_384] do
        names = Enum.map(1..size, &"name_#{&1}")

        Task.async(fn ->
          :erlang.garbage_collect()
          {:reductions, before} = Process.info(self(), :reductions)
          assert {:ok, ^names} = normalize_needs(names)
          {:reductions, after_count} = Process.info(self(), :reductions)
          after_count - before
        end)
        |> Task.await()
      end

    [small, large] = counts
    assert large < small * 16
  end

  test "Codec preserves broad values and ordered nested error groups" do
    {document, registry} = document()
    values = Enum.map(0..255, &[&1, &1 + 1])
    assert {:ok, %{output: ^values}} = Codec.diagnose(%{document | "output" => values}, registry)

    invalid =
      Enum.map(0..127, fn _ ->
        [
          %{"$ref" => %{"source" => "unsupported", "component" => 42, "path" => 42}},
          %{"$type" => "atom"}
        ]
      end)

    assert {:error, %Error.Invalid{errors: errors}} =
             Codec.diagnose(%{document | "output" => invalid}, registry)

    assert Enum.map(errors, & &1.details.path) ==
             Enum.flat_map(0..127, fn index ->
               Enum.map(["source", "component", "path"], &["output", index, 0, "$ref", &1]) ++
                 [["output", index, 1, "id"]]
             end)
  end

  test "Codec reports duplicate occurrences in source order" do
    {document, registry} = document()
    [step] = document["components"]
    names = ["first", "second", "second", "first", "first", "second"]
    components = Enum.map(names, &%{step | "name" => &1})

    assert {:error, %Error.Invalid{errors: errors}} =
             Codec.diagnose(%{document | "components" => components}, registry)

    assert Enum.map(errors, &{&1.details.name, &1.details.path}) ==
             Enum.map(Enum.with_index(Enum.drop(names, 2), 2), fn {name, index} ->
               {name, ["components", index, "name"]}
             end)
  end

  test "Codec checks values after errors and preserves mixed nested error order" do
    {document, registry} = document()
    missing_atom = %{"$type" => "atom"}
    bad_ref = %{"$ref" => %{"source" => "unsupported", "component" => 42, "path" => 42}}

    output = [
      [1, [], 2],
      missing_atom,
      [[], bad_ref, [3, 4], missing_atom],
      %{"$type" => "map", "entries" => [%{"key" => "ok", "value" => []}]},
      bad_ref
    ]

    assert {:error, %Error.Invalid{errors: [first | _] = errors}} =
             Codec.diagnose(%{document | "output" => output}, registry)

    assert Enum.map(errors, & &1.details.path) ==
             [["output", 1, "id"]] ++
               Enum.map(["source", "component", "path"], &["output", 2, 1, "$ref", &1]) ++
               [["output", 2, 3, "id"]] ++
               Enum.map(["source", "component", "path"], &["output", 4, "$ref", &1])

    assert {:error, decoded_error} = Codec.decode(%{document | "output" => output}, registry)
    assert decoded_error.message == first.message
    assert decoded_error.details == first.details

    valid = [[], [1, [], 2], []]
    assert {:ok, %{output: ^valid}} = Codec.diagnose(%{document | "output" => valid}, registry)
  end

  test "Codec preserves duplicate map key order and its first error" do
    {document, registry} = document()

    entries =
      Enum.map(["first", "second", "second", "first", "second"], &%{"key" => &1, "value" => 1})

    invalid = %{document | "output" => %{"$type" => "map", "entries" => entries}}

    assert {:error, %Error.Invalid{errors: [first | _] = errors}} =
             Codec.diagnose(invalid, registry)

    assert Enum.map(errors, & &1.details.path) ==
             Enum.map(2..4, &["output", "entries", &1, "key"])

    assert {:error, decoded_error} = Codec.decode(invalid, registry)
    assert decoded_error.message == first.message
    assert decoded_error.details == first.details
  end

  defp normalize_needs(needs) do
    case Definition.component(%{
           kind: :step,
           name: "component",
           action: UnloadedAction,
           needs: needs
         }) do
      {:ok, {_name, node}} -> {:ok, Definition.needs(node)}
      {:error, error} -> {:error, error}
    end
  end
end
