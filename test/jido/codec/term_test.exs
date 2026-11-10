defmodule Jido.Codec.TermTest do
  use ExUnit.Case, async: true

  alias Jido.Codec.Term

  test "map validation reports the first invalid key or value with its exact path" do
    assert {:error, [:payload, {:map_key, 0}]} =
             Term.validate(%{self() => make_ref()}, :payload)

    assert {:error, [:payload, :first]} =
             Term.validate(%{second: self(), first: make_ref()}, :payload)

    assert {:error, [:payload, :second, 1]} =
             Term.validate(%{first: :ok, second: {:ok, self()}}, :payload)

    assert :ok = Term.validate(%{first: :ok, second: {:ok, [1, nil]}}, :payload)
  end

  test "portable validation rejects every local runtime value" do
    port = Port.open({:spawn_executable, System.find_executable("true")}, [])

    on_exit(fn ->
      try do
        Port.close(port)
      rescue
        # The spawned program can exit at any moment, which closes the port.
        ArgumentError -> :ok
      end
    end)

    values = [
      {self(), [:payload]},
      {port, [:payload]},
      {make_ref(), [:payload]},
      {fn -> :runtime end, [:payload]},
      {[1 | :tail], [:payload, 1]},
      {<<1::size(1)>>, [:payload]}
    ]

    for {value, path} <- values do
      assert {:error, ^path} = Term.validate(value, :payload)
      refute Term.valid?(value)
    end

    assert Term.valid?(%{value: [1, 2.0, nil, true, {:ok, "done"}]})
  end

  test "diagnostic paths have fixed segment and depth bounds" do
    deep = Enum.reduce(1..30, self(), fn index, value -> %{index => value} end)
    assert {:error, path} = Term.validate(deep, :payload)
    assert length(path) == 20

    long_binary = String.duplicate("b", 100)
    long_atom = :aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    for key <- [long_binary, long_atom] do
      assert {:error, [:payload, segment]} = Term.validate(%{key => self()}, :payload)
      assert is_binary(segment)
      assert byte_size(segment) == 64
    end

    assert {:error, [root]} =
             Term.validate(self(), [String.duplicate("r", 100)])

    assert byte_size(root) == 64
  end

  test "integer path segments keep only the exact bounded range" do
    max = 9_999_999_999_999_999

    for key <- [-max, max] do
      assert {:error, [:payload, ^key]} = Term.validate(%{key => self()}, :payload)
    end

    for key <- [-max - 1, max + 1] do
      assert {:error, [:payload, {:map_value, 0}]} =
               Term.validate(%{key => self()}, :payload)
    end

    assert {:error, [:payload, {:map_value, 0}]} =
             Term.validate(%{{:compound, :key} => self()}, :payload)
  end

  test "binary path segments keep at most their first 64 bytes" do
    exact = "A" <> String.duplicate("b", 63)
    over = exact <> "Z"

    assert byte_size(exact) == 64
    assert {:error, [:payload, ^exact]} = Term.validate(%{exact => self()}, :payload)
    assert {:error, [:payload, ^exact]} = Term.validate(%{over => self()}, :payload)
  end

  test "collection validation keeps deterministic order and the first invalid list item" do
    assert {:error, [:payload, :a]} =
             Term.validate(%{a: self(), b: make_ref()}, :payload)

    assert {:error, [:payload, 0]} = Term.validate([self()], :payload)
    assert {:error, []} = Term.validate(self(), 1)
  end
end
