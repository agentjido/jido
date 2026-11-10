defmodule Jido.Exec.FactTest do
  use ExUnit.Case, async: true

  alias Jido.Exec.Fact, as: JidoFact
  alias Runic.Identity.CanonicalError
  alias Runic.Workflow.Fact, as: RunicFact

  defmodule Echo do
    use Jido.Action, name: "fact_echo"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  test "local facts preserve improper lists at the root and in nested values" do
    reference = make_ref()

    for value <- [[1 | :tail], [reference | :tail], %{nested: {[1 | :tail], [[2 | :tail]]}}] do
      assert value === value |> JidoFact.local_root() |> JidoFact.value()
    end
  end

  test "native facts propagate local identity from wrapped improper lists" do
    root = JidoFact.local_root([1 | :tail])
    native_fact = RunicFact.new(value: [root.value], ancestry: {:native_join, root.hash})

    child =
      JidoFact.child(native_fact,
        value: %{payload: [2 | :tail]},
        ancestry: {:jido_node, native_fact.hash}
      )

    assert JidoFact.value(child) === %{payload: [2 | :tail]}
  end

  test "unwrap handles improper native lists containing wrapped values" do
    reference = make_ref()
    value = [JidoFact.local_value(reference) | :tail]

    assert JidoFact.unwrap(value) === [reference | :tail]

    for input <- [value, [1 | :tail]] do
      opts = JidoFact.child_options(input, %{}, value: [1 | :tail])
      assert opts[:meta] == %{jido: %{identity_mode: :local}}
      assert JidoFact.unwrap(opts[:value]) === [1 | :tail]
    end
  end

  test "run/4 preserves improper lists in Action input and output" do
    params = %{payload: [1 | :tail], nested: %{values: [[2 | :tail]]}}

    assert {:ok, ^params} = Jido.Exec.run(Echo, params)
  end

  test "local facts preserve process-local values across native Runic facts" do
    reference = make_ref()
    root = JidoFact.local_root(%{reference: reference})

    native_fact =
      RunicFact.new(
        value: [root.value],
        ancestry: {:native_join, root.hash}
      )

    child =
      JidoFact.child(native_fact,
        value: %{reference: reference, uri: URI.parse("/home")},
        ancestry: {:jido_node, native_fact.hash}
      )

    assert JidoFact.value(child) == %{reference: reference, uri: URI.parse("/home")}
  end

  test "local facts bound deeply nested identity documents" do
    value = Enum.reduce(1..100, :leaf, fn _index, nested -> [nested] end)

    assert value == value |> JidoFact.local_root() |> JidoFact.value()
  end

  test "canonical facts still reject process-local child values" do
    parent = RunicFact.new(value: %{})

    assert_raise CanonicalError, fn ->
      JidoFact.child(parent, value: make_ref(), ancestry: {:jido_node, parent.hash})
    end
  end
end
