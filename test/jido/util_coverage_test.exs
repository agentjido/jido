defmodule JidoTest.UtilCoverageTest do
  use JidoTest.Case, async: true

  alias Jido.Util
  alias JidoTest.TestActions

  describe "validate_actions/2 with opts" do
    test "validates valid action module with opts" do
      assert :ok = Util.validate_actions(TestActions.BasicAction, validate: true)
    end

    test "rejects invalid action module with opts" do
      assert {:error, %Jido.Error.ValidationError{}} =
               Util.validate_actions(NonExistentModule, validate: true)
    end

    test "validates valid action list with opts" do
      assert :ok = Util.validate_actions([TestActions.BasicAction], validate: true)
    end

    test "rejects invalid action list with opts" do
      assert {:error, %Jido.Error.ValidationError{}} =
               Util.validate_actions([NonExistentModule], validate: true)
    end
  end

  describe "via_tuple/2 with string name in tuple" do
    test "preserves string name in tuple form" do
      result = Util.via_tuple({"string_name", MyRegistry})
      assert {:via, Registry, {MyRegistry, "string_name"}} = result
    end

    test "raises when registry option is missing" do
      assert_raise ArgumentError, ":registry option is required", fn ->
        Util.via_tuple(:my_process)
      end
    end
  end

  describe "whereis/2 with registered process" do
    test "finds registered process via tuple form", %{jido: jido} do
      registry = Jido.registry_name(jido)
      name = "test_process_#{System.unique_integer()}"

      {:ok, _} = Registry.register(registry, name, nil)

      assert {:ok, pid} = Util.whereis({name, registry})
      assert pid == self()
    end

    test "finds registered process via atom name with opts", %{jido: jido} do
      registry = Jido.registry_name(jido)
      name = :"test_atom_#{System.unique_integer()}"
      string_name = Atom.to_string(name)

      {:ok, _} = Registry.register(registry, string_name, nil)

      assert {:ok, pid} = Util.whereis(name, registry: registry)
      assert pid == self()
    end

    test "finds registered process via string name in tuple", %{jido: jido} do
      registry = Jido.registry_name(jido)
      name = "string_lookup_#{System.unique_integer()}"

      {:ok, _} = Registry.register(registry, name, nil)

      assert {:ok, pid} = Util.whereis({name, registry})
      assert pid == self()
    end

    test "raises when registry option is missing" do
      assert_raise ArgumentError, ":registry option is required", fn ->
        Util.whereis(:my_process)
      end
    end
  end
end
