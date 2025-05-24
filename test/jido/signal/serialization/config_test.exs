defmodule Jido.Signal.Serialization.ConfigTest do
  use ExUnit.Case, async: false

  alias Jido.Signal.Serialization.{
    Config,
    JsonSerializer,
    ErlangTermSerializer,
    ModuleNameTypeProvider
  }

  setup do
    # Store original config
    original_serializer = Application.get_env(:jido, :default_serializer)
    original_type_provider = Application.get_env(:jido, :default_type_provider)

    on_exit(fn ->
      # Restore original config
      if original_serializer do
        Application.put_env(:jido, :default_serializer, original_serializer)
      else
        Application.delete_env(:jido, :default_serializer)
      end

      if original_type_provider do
        Application.put_env(:jido, :default_type_provider, original_type_provider)
      else
        Application.delete_env(:jido, :default_type_provider)
      end
    end)

    :ok
  end

  describe "default_serializer/0" do
    test "returns JsonSerializer by default" do
      Application.delete_env(:jido, :default_serializer)
      assert Config.default_serializer() == JsonSerializer
    end

    test "returns configured serializer" do
      Application.put_env(:jido, :default_serializer, ErlangTermSerializer)
      assert Config.default_serializer() == ErlangTermSerializer
    end
  end

  describe "default_type_provider/0" do
    test "returns ModuleNameTypeProvider by default" do
      Application.delete_env(:jido, :default_type_provider)
      assert Config.default_type_provider() == ModuleNameTypeProvider
    end

    test "returns configured type provider" do
      Application.put_env(:jido, :default_type_provider, SomeCustomProvider)
      assert Config.default_type_provider() == SomeCustomProvider
    end
  end

  describe "set_default_serializer/1" do
    test "sets the default serializer" do
      Config.set_default_serializer(ErlangTermSerializer)
      assert Config.default_serializer() == ErlangTermSerializer
    end
  end

  describe "set_default_type_provider/1" do
    test "sets the default type provider" do
      Config.set_default_type_provider(SomeCustomProvider)
      assert Config.default_type_provider() == SomeCustomProvider
    end
  end

  describe "all/0" do
    test "returns all configuration" do
      Config.set_default_serializer(ErlangTermSerializer)
      Config.set_default_type_provider(ModuleNameTypeProvider)

      config = Config.all()

      assert config[:default_serializer] == ErlangTermSerializer
      assert config[:default_type_provider] == ModuleNameTypeProvider
    end
  end

  describe "validate_serializer/1" do
    test "validates valid serializer" do
      assert Config.validate_serializer(JsonSerializer) == :ok
      assert Config.validate_serializer(ErlangTermSerializer) == :ok
    end

    test "returns error for invalid serializer" do
      {:error, message} = Config.validate_serializer(String)
      assert message =~ "does not implement"
      assert message =~ "Serializer behaviour"
    end

    test "returns error for non-existent module" do
      {:error, message} = Config.validate_serializer(NonExistentModule)
      assert message =~ "module not found"
    end
  end

  describe "validate_type_provider/1" do
    test "validates valid type provider" do
      assert Config.validate_type_provider(ModuleNameTypeProvider) == :ok
    end

    test "returns error for invalid type provider" do
      {:error, message} = Config.validate_type_provider(String)
      assert message =~ "does not implement"
      assert message =~ "TypeProvider behaviour"
    end

    test "returns error for non-existent module" do
      {:error, message} = Config.validate_type_provider(NonExistentModule)
      assert message =~ "module not found"
    end
  end

  describe "validate/0" do
    test "validates current configuration successfully" do
      Config.set_default_serializer(JsonSerializer)
      Config.set_default_type_provider(ModuleNameTypeProvider)

      assert Config.validate() == :ok
    end

    test "returns errors for invalid configuration" do
      Config.set_default_serializer(String)
      Config.set_default_type_provider(Integer)

      {:error, errors} = Config.validate()

      assert length(errors) == 2
      assert Enum.any?(errors, &String.contains?(&1, "Serializer behaviour"))
      assert Enum.any?(errors, &String.contains?(&1, "TypeProvider behaviour"))
    end
  end
end
