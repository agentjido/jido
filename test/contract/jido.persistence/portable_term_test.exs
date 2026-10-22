defmodule JidoTest.Persistence.PortableTermTest do
  use Covenant.Case, component: "jido.persistence", async: true

  alias Jido.PortableTerm

  @tag obligation: "jido.persistence.I9"
  test "map validation reports the first invalid key or value with its exact path" do
    assert {:error, [:payload, {:map_key, 0}]} =
             PortableTerm.validate(%{self() => make_ref()}, :payload)

    assert {:error, [:payload, :first]} =
             PortableTerm.validate(%{second: self(), first: make_ref()}, :payload)

    assert {:error, [:payload, :second, 1]} =
             PortableTerm.validate(%{first: :ok, second: {:ok, self()}}, :payload)

    assert :ok = PortableTerm.validate(%{first: :ok, second: {:ok, [1, nil]}}, :payload)
  end

  @tag obligation: "jido.persistence.I9"
  test "portable validation rejects every local runtime value" do
    port = Port.open({:spawn_executable, System.find_executable("true")}, [])
    on_exit(fn -> if Port.info(port), do: Port.close(port) end)

    values = [
      {self(), [:payload]},
      {port, [:payload]},
      {make_ref(), [:payload]},
      {fn -> :runtime end, [:payload]},
      {[1 | :tail], [:payload, 1]},
      {<<1::size(1)>>, [:payload]}
    ]

    for {value, path} <- values do
      assert {:error, ^path} = PortableTerm.validate(value, :payload)
      refute PortableTerm.valid?(value)
    end

    assert PortableTerm.valid?(%{value: [1, 2.0, nil, true, {:ok, "done"}]})
  end

  @tag obligation: "jido.persistence.I9"
  test "diagnostic paths have fixed segment and depth bounds" do
    deep = Enum.reduce(1..30, self(), fn index, value -> %{index => value} end)
    assert {:error, path} = PortableTerm.validate(deep, :payload)
    assert length(path) == 20

    long_binary = String.duplicate("b", 100)
    long_atom = :aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    for key <- [long_binary, long_atom] do
      assert {:error, [:payload, segment]} = PortableTerm.validate(%{key => self()}, :payload)
      assert is_binary(segment)
      assert byte_size(segment) == 64
    end

    assert {:error, [root]} =
             PortableTerm.validate(self(), [String.duplicate("r", 100)])

    assert byte_size(root) == 64
  end

  @tag obligation: "jido.persistence.I9"
  test "integer path segments keep only the exact bounded range" do
    max = 9_999_999_999_999_999

    for key <- [-max, max] do
      assert {:error, [:payload, ^key]} = PortableTerm.validate(%{key => self()}, :payload)
    end

    for key <- [-max - 1, max + 1] do
      assert {:error, [:payload, {:map_value, 0}]} =
               PortableTerm.validate(%{key => self()}, :payload)
    end

    assert {:error, [:payload, {:map_value, 0}]} =
             PortableTerm.validate(%{{:compound, :key} => self()}, :payload)
  end

  @tag obligation: "jido.persistence.I9"
  test "binary path segments keep at most their first 64 bytes" do
    exact = "A" <> String.duplicate("b", 63)
    over = exact <> "Z"

    assert byte_size(exact) == 64
    assert {:error, [:payload, ^exact]} = PortableTerm.validate(%{exact => self()}, :payload)
    assert {:error, [:payload, ^exact]} = PortableTerm.validate(%{over => self()}, :payload)
  end

  @tag obligation: "jido.persistence.I9"
  test "collection validation keeps deterministic order and the first invalid list item" do
    assert {:error, [:payload, :a]} =
             PortableTerm.validate(%{a: self(), b: make_ref()}, :payload)

    assert {:error, [:payload, 0]} = PortableTerm.validate([self()], :payload)
    assert {:error, []} = PortableTerm.validate(self(), 1)
  end
end
