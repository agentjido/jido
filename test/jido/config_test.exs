defmodule Jido.ConfigTest do
  use ExUnit.Case, async: false

  alias Jido.Config
  alias Jido.Error.ValidationError

  setup do
    name = "JIDO_CONFIG_TEST_#{System.unique_integer([:positive])}"
    on_exit(fn -> System.delete_env(name) end)
    %{name: name}
  end

  test "env creates static data without reading the environment", %{name: name} do
    assert System.fetch_env(name) == :error
    assert Config.env(name) == {:env, name}
  end

  test "env rejects invalid variable names" do
    for name <- [nil, :key, 1, [], "", "A=B", "A\0B", <<255>>] do
      assert_raise ArgumentError, fn -> Config.env(name) end
    end
  end

  test "resolution reads the current value and keeps strings unchanged", %{name: name} do
    reference = Config.env(name)

    for value <- ["first", "second", "", "false", "123"] do
      System.put_env(name, value)
      assert Config.resolve(reference) == {:ok, value}
    end
  end

  test "resolution walks nested values and preserves keys, tuple shape and keyword order", %{
    name: name
  } do
    System.put_env(name, "secret")
    reference = Config.env(name)

    config = %{
      reference => "literal key",
      env: name,
      connections: [%{credentials: [token: reference, token: "override"]}],
      tuple: {:adapter, reference, [reference]}
    }

    assert {:ok,
            %{
              ^reference => "literal key",
              env: ^name,
              connections: [%{credentials: [token: "secret", token: "override"]}],
              tuple: {:adapter, "secret", ["secret"]}
            }} = Config.resolve(config)
  end

  test "ordinary values and structs are unchanged" do
    for value <- [nil, false, 0, :literal, "literal", [], {}, self(), %URI{host: "example.com"}] do
      assert Config.resolve(value) === {:ok, value}
    end
  end

  test "missing variables return structured errors with the configuration path", %{name: name} do
    config = %{connections: [%{credentials: [token: Config.env(name)]}]}

    assert {:error, %ValidationError{kind: :config, details: details}} =
             Config.resolve(config)

    assert details == %{
             code: :missing_env,
             name: name,
             path: [:connections, 0, :credentials, :token]
           }

    assert {:error, %ValidationError{details: %{code: :missing_env, name: ^name, path: [1]}}} =
             Config.resolve({:adapter, Config.env(name)})

    assert {:error,
            %ValidationError{details: %{code: :missing_env, name: ^name, path: [:rooms, 0]}}} =
             Config.resolve(%{rooms: [Config.env(name)]})
  end

  test "invalid stored references return errors without exposing sibling values" do
    for name <- [nil, 123, "", "A=B", "A\0B", <<255>>] do
      assert {:error, %ValidationError{kind: :config, details: details} = error} =
               Config.resolve(%{credentials: %{token: {:env, name}}, secret: "private-value"})

      assert details == %{code: :invalid_env, path: [:credentials, :token]}
      refute inspect(error) =~ "private-value"
    end
  end

  test "improper lists return a structured configuration error" do
    assert {:error, %ValidationError{kind: :config, details: details}} =
             Config.resolve(%{values: [1 | :invalid]})

    assert details == %{code: :invalid_config, path: [:values, 1]}
  end
end
