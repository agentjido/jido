defmodule JidoTest.UtilTest do
  use JidoTest.Case, async: true

  alias Jido.Util
  alias JidoTest.TestActions

  describe "generate_id/0" do
    test "generates unique non-empty binary identifiers" do
      id1 = Util.generate_id()
      id2 = Util.generate_id()

      assert is_binary(id1)
      assert is_binary(id2)
      assert String.length(id1) > 0
      refute id1 == id2
    end
  end

  describe "string_to_binary!/1" do
    test "returns binary string unchanged" do
      assert Util.string_to_binary!("hello") == "hello"
    end
  end

  describe "validate_name/2" do
    test "validates valid names" do
      assert {:ok, "valid_name"} = Util.validate_name("valid_name")
      assert {:ok, "myAction123"} = Util.validate_name("myAction123")
      assert :ok = Util.validate_name("valid_name", validate: true)
    end

    test "rejects invalid names" do
      invalid_names = ["123action", "invalid-name", "invalid name", 123]

      for name <- invalid_names do
        assert {:error, _} = Util.validate_name(name),
               "expected #{inspect(name)} to be rejected"
      end
    end

    test "rejects invalid names with validate: true option" do
      for name <- ["invalid-name", 123] do
        assert {:error, _} = Util.validate_name(name, validate: true),
               "expected #{inspect(name)} to be rejected with validate: true"
      end
    end

    test "returns structured validation errors" do
      assert {:error, %Jido.Error.ValidationError{} = err} = Util.validate_name("invalid-name")
      assert err.message =~ "must start with a letter"
    end
  end

  describe "validate_actions/1" do
    test "validates valid action modules" do
      assert {:ok, [TestActions.BasicAction]} = Util.validate_actions([TestActions.BasicAction])
      assert {:ok, TestActions.NoSchema} = Util.validate_actions(TestActions.NoSchema)
    end

    test "rejects invalid action modules" do
      invalid_inputs = [
        [NonExistentModule],
        NonExistentModule,
        Enum
      ]

      for invalid <- invalid_inputs do
        assert {:error, _} = Util.validate_actions(invalid),
               "expected #{inspect(invalid)} to be rejected"
      end
    end

    test "returns structured validation errors for invalid actions" do
      assert {:error, %Jido.Error.ValidationError{} = err} = Util.validate_actions([Enum])
      assert err.kind == :action
    end
  end

  describe "validate_module/1" do
    test "validates existing module" do
      assert {:ok, Enum} = Util.validate_module(Enum)
    end

    test "rejects invalid module inputs" do
      for input <- [:non_existent_module, "not_an_atom"] do
        assert {:error, _} = Util.validate_module(input),
               "expected #{inspect(input)} to be rejected"
      end
    end
  end

  describe "validate_module_compiled/1" do
    test "validates compilable module" do
      assert {:ok, Enum} = Util.validate_module_compiled(Enum)
    end

    test "rejects invalid module inputs" do
      for input <- [:definitely_not_a_module, "not_an_atom"] do
        assert {:error, _} = Util.validate_module_compiled(input),
               "expected #{inspect(input)} to be rejected"
      end
    end
  end

  describe "pluck/2" do
    test "extracts field from list of maps" do
      list = [%{name: "a", value: 1}, %{name: "b", value: 2}]
      assert Util.pluck(list, :name) == ["a", "b"]
    end

    test "returns nil for missing fields" do
      list = [%{name: "a"}, %{other: "b"}]
      assert Util.pluck(list, :name) == ["a", nil]
    end

    test "handles empty list" do
      assert Util.pluck([], :name) == []
    end
  end

  describe "via_tuple/2" do
    test "creates via tuple with default and custom registry", %{jido: jido} do
      registry = Jido.registry_name(jido)
      result = Util.via_tuple(:my_process, registry: registry)
      assert {:via, Registry, {^registry, "my_process"}} = result

      result2 = Util.via_tuple(:my_process, registry: MyRegistry)
      assert {:via, Registry, {MyRegistry, "my_process"}} = result2

      result3 = Util.via_tuple({:my_process, MyRegistry})
      assert {:via, Registry, {MyRegistry, "my_process"}} = result3
    end

    test "converts atom name to string and preserves string name", %{jido: jido} do
      registry = Jido.registry_name(jido)
      {:via, Registry, {_, name1}} = Util.via_tuple(:atom_name, registry: registry)
      assert is_binary(name1)

      {:via, Registry, {_, name2}} = Util.via_tuple("string_name", registry: registry)
      assert name2 == "string_name"
    end
  end

  describe "whereis/2" do
    test "returns pid when given pid" do
      pid = self()
      assert {:ok, ^pid} = Util.whereis(pid)
    end

    test "returns not_found for unregistered names", %{jido: jido} do
      registry = Jido.registry_name(jido)

      inputs = [
        :unregistered_process_xyz,
        {:unregistered_xyz, registry},
        :some_atom_name_xyz
      ]

      for input <- inputs do
        assert {:error, :not_found} = Util.whereis(input, registry: registry),
               "expected #{inspect(input)} to return :not_found"
      end
    end

    test "uses custom registry option", %{jido: jido} do
      registry = Jido.registry_name(jido)
      assert {:error, :not_found} = Util.whereis(:some_name_xyz, registry: registry)
    end
  end

  describe "cond_log/4" do
    test "exercises logging branches and returns :ok" do
      assert :ok = Util.cond_log(:debug, :info, "threshold <= level")
      assert :ok = Util.cond_log(:info, :debug, "threshold > level")
      assert :ok = Util.cond_log(:info, :info, "threshold equals level")
      assert :ok = Util.cond_log(:invalid, :info, "invalid threshold")
      assert :ok = Util.cond_log(:info, :invalid, "invalid level")
      assert :ok = Util.cond_log(:debug, :info, "with opts", domain: [:test])
    end
  end
end
