defmodule JidoTest.Util.DeepMergeTest do
  use ExUnit.Case, async: true

  alias Jido.Util.DeepMerge

  describe "merge/2" do
    test "deep merges maps" do
      assert DeepMerge.merge(%{config: %{a: 1, b: 2}}, %{config: %{b: 3, c: 4}}) ==
               %{config: %{a: 1, b: 3, c: 4}}
    end

    test "deep merges keyword lists" do
      left = %{config: [a: 1, b: [x: 10, y: 9]]}
      right = %{config: [b: [y: 20, z: 30], c: 4]}

      assert DeepMerge.merge(left, right) ==
               %{config: [a: 1, b: [x: 10, y: 20, z: 30], c: 4]}
    end

    test "deep merges top-level keyword lists" do
      assert DeepMerge.merge([a: 1, b: [x: 10, y: 9]], b: [y: 20, z: 30], c: 4) ==
               [a: 1, b: [x: 10, y: 20, z: 30], c: 4]
    end

    test "preserves keyword list when override is empty list" do
      assert DeepMerge.merge(%{config: [a: 1]}, %{config: []}) == %{config: [a: 1]}
    end

    test "replaces structs rather than merging them as maps" do
      assert DeepMerge.merge(%{endpoint: %URI{scheme: "http"}}, %{endpoint: %{scheme: "https"}}) ==
               %{endpoint: %{scheme: "https"}}

      assert DeepMerge.merge(%{endpoint: %{scheme: "http"}}, %{
               endpoint: %URI{scheme: "https", host: "example.com"}
             }) == %{endpoint: %URI{scheme: "https", host: "example.com"}}
    end

    test "uses right-side value for non-mergeable conflicts" do
      assert DeepMerge.merge(%{value: %{nested: true}}, %{value: nil}) == %{value: nil}
      assert DeepMerge.merge(%{value: [1, 2]}, %{value: []}) == %{value: []}
    end

    test "replaces non-keyword tuple lists instead of treating them as keyword lists" do
      left = %{entries: [{"a", %{left: true}}]}
      right = %{entries: [{"a", %{right: true}}]}

      assert DeepMerge.merge(left, right) == right
    end
  end
end
