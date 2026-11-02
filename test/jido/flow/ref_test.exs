defmodule Jido.Flow.RefTest do
  use ExUnit.Case, async: true

  alias Jido.Flow.Error.InvalidDefinitionError
  alias Jido.Flow.Ref

  test "the reference grammar has one source, optional component, and path" do
    assert Ref.input(:id) == %Ref{source: :input, component: nil, path: [:id]}

    assert Ref.result(:load, [:item, 0]) == %Ref{
             source: :result,
             component: "load",
             path: [:item, 0]
           }

    refute Map.has_key?(Map.from_struct(Ref.input(:id)), :value)
  end

  test "result is the only source that accepts a component" do
    assert :ok = Ref.validate(Ref.result("load"))

    assert {:error, %InvalidDefinitionError{}} =
             Ref.validate(%Ref{source: :input, component: "load", path: []})

    assert {:error, %InvalidDefinitionError{}} =
             Ref.validate(%Ref{source: :result, component: nil, path: []})
  end

  test "local sources are checked against the owner scope" do
    assert :ok = Ref.validate(Ref.item(), :map_params)
    assert :ok = Ref.validate(Ref.accumulator(), :reduce_params)
    assert :ok = Ref.validate(Ref.state(), :iterate_completion)
    assert {:error, %InvalidDefinitionError{}} = Ref.validate(Ref.state(), :flow)
    assert {:error, %InvalidDefinitionError{}} = Ref.validate(Ref.item(), :iterate_params)
  end

  test "paths contain only portable path segments" do
    assert :ok = Ref.validate(Ref.input([:payload, "items", 0]))
    assert {:error, %InvalidDefinitionError{}} = Ref.validate(Ref.input([-1]))
    assert {:error, %InvalidDefinitionError{}} = Ref.validate(Ref.input([%{}]))
  end

  test "nil is rejected at each path position for every source with a path" do
    for path <- [[nil], [nil, :value], [:payload, nil, :value], [:payload, nil]],
        ref <- path_refs(path) do
      assert {:error,
              %InvalidDefinitionError{
                details: %{reason: :path, segment: nil, ref: ^ref}
              }} = Ref.validate(ref, :any)
    end
  end

  test "invalid UTF-8 is rejected at every path position for every source with a path" do
    for segment <- [<<255>>, <<0xC3>>, <<0xC0, 0xAF>>, <<0xED, 0xA0, 0x80>>],
        path <- [[segment], [segment, :value], [:payload, segment, 0], [:payload, segment]],
        ref <- path_refs(path) do
      assert {:error,
              %InvalidDefinitionError{
                message: "invalid flow ref",
                details: %{reason: :path, segment: ^segment, ref: ^ref}
              }} = Ref.validate(ref, :any)
    end
  end

  test "valid Unicode and empty strings remain valid path segments" do
    for segment <- ["", "café", "項目🌿", "e\u0301", <<0>>],
        ref <- path_refs([:payload, segment, 0, true, false]) do
      assert :ok = Ref.validate(ref, :any)
    end
  end

  test "improper paths return a structured error for every source with a path" do
    for path <- [[:payload | :tail], [:payload, :value | nil]],
        ref <- path_refs(path) do
      assert {:error,
              %InvalidDefinitionError{
                details: %{reason: :path, segment: ^path, ref: ^ref}
              }} = Ref.validate(ref, :any)
    end
  end

  test "supported segments and empty paths remain valid for every source with a path" do
    for path <- [nil, [], :value, "value", 0, [:payload, "items", 0, true, false]],
        ref <- path_refs(path) do
      assert :ok = Ref.validate(ref, :any)
    end

    assert Ref.input(nil) == Ref.input([])
  end

  test "unsupported segments and non-list canonical paths return structured errors" do
    for segment <- [-1, 1.5, %{}, [], {:value}, self(), make_ref(), fn -> :value end],
        ref <- path_refs([:payload, segment]) do
      assert {:error, %InvalidDefinitionError{details: %{reason: :path, segment: ^segment}}} =
               Ref.validate(ref, :any)
    end

    for path <- [nil, :value, "value", 0, %{}], ref <- path_refs([]) do
      assert {:error, %InvalidDefinitionError{details: %{reason: :path, segment: ^path}}} =
               Ref.validate(%{ref | path: path}, :any)
    end
  end

  test "index and identifier sources require an empty path" do
    for ref <- [Ref.item_index(), Ref.item_id(), Ref.iteration_index()] do
      assert :ok = Ref.validate(ref, :any)

      for path <- [[nil], [:value], [:value | :tail], :value] do
        assert {:error, %InvalidDefinitionError{details: %{reason: :shape}}} =
                 Ref.validate(%{ref | path: path}, :any)
      end
    end
  end

  defp path_refs(path) do
    [
      Ref.input(path),
      Ref.context(path),
      Ref.result("load", path),
      Ref.item(path),
      Ref.accumulator(path),
      Ref.state(path),
      Ref.body_result(path)
    ]
  end
end
