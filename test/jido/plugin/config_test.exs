defmodule JidoTest.Plugin.ConfigTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin.Config

  defmodule PluginWithoutOtpApp do
    @moduledoc false
    use Jido.Plugin,
      name: "no_otp_app",
      state_key: :no_otp_app,
      actions: [JidoTest.PluginTestAction]
  end

  defmodule PluginWithOtpApp do
    @moduledoc false
    use Jido.Plugin,
      name: "with_otp_app",
      state_key: :with_otp_app,
      otp_app: :jido,
      actions: [JidoTest.PluginTestAction]
  end

  defmodule PluginWithConfigSchema do
    @moduledoc false
    use Jido.Plugin,
      name: "with_schema",
      state_key: :with_schema,
      otp_app: :jido,
      actions: [JidoTest.PluginTestAction],
      config_schema:
        Zoi.object(%{
          token: Zoi.string(),
          channel: Zoi.string() |> Zoi.optional(),
          timeout: Zoi.integer() |> Zoi.default(5000)
        })
  end

  describe "resolve_config/2" do
    test "returns empty map when no otp_app and no overrides" do
      assert {:ok, %{}} = Config.resolve_config(PluginWithoutOtpApp, %{})
    end

    test "returns overrides when no otp_app" do
      assert {:ok, %{token: "abc"}} = Config.resolve_config(PluginWithoutOtpApp, %{token: "abc"})
    end

    test "loads config from application env when otp_app is set" do
      Application.put_env(:jido, PluginWithOtpApp, token: "env-token", channel: "#general")

      on_exit(fn ->
        Application.delete_env(:jido, PluginWithOtpApp)
      end)

      {:ok, config} = Config.resolve_config(PluginWithOtpApp, %{})
      assert config[:token] == "env-token"
      assert config[:channel] == "#general"
    end

    test "overrides win over app env config" do
      Application.put_env(:jido, PluginWithOtpApp, token: "env-token", channel: "#general")

      on_exit(fn ->
        Application.delete_env(:jido, PluginWithOtpApp)
      end)

      {:ok, config} = Config.resolve_config(PluginWithOtpApp, %{channel: "#support"})
      assert config[:token] == "env-token"
      assert config[:channel] == "#support"
    end

    test "validates config against config_schema when present" do
      Application.put_env(:jido, PluginWithConfigSchema, [])

      on_exit(fn ->
        Application.delete_env(:jido, PluginWithConfigSchema)
      end)

      {:ok, config} = Config.resolve_config(PluginWithConfigSchema, %{token: "my-token"})
      assert config.token == "my-token"
      assert config.timeout == 5000
      refute Map.has_key?(config, :channel)
    end

    test "returns error when config_schema validation fails" do
      Application.put_env(:jido, PluginWithConfigSchema, [])

      on_exit(fn ->
        Application.delete_env(:jido, PluginWithConfigSchema)
      end)

      assert {:error, _errors} = Config.resolve_config(PluginWithConfigSchema, %{})
    end

    test "handles keyword list config from app env" do
      Application.put_env(:jido, PluginWithOtpApp, token: "keyword-token")

      on_exit(fn ->
        Application.delete_env(:jido, PluginWithOtpApp)
      end)

      {:ok, config} = Config.resolve_config(PluginWithOtpApp, %{})
      assert config[:token] == "keyword-token"
    end

    test "handles map config from app env" do
      Application.put_env(:jido, PluginWithOtpApp, %{token: "map-token"})

      on_exit(fn ->
        Application.delete_env(:jido, PluginWithOtpApp)
      end)

      {:ok, config} = Config.resolve_config(PluginWithOtpApp, %{})
      assert config[:token] == "map-token"
    end
  end

  describe "resolve_config!/2" do
    test "returns config on success" do
      config = Config.resolve_config!(PluginWithoutOtpApp, %{token: "abc"})
      assert config == %{token: "abc"}
    end

    test "raises on validation error" do
      Application.put_env(:jido, PluginWithConfigSchema, [])

      on_exit(fn ->
        Application.delete_env(:jido, PluginWithConfigSchema)
      end)

      assert_raise ArgumentError, ~r/Config validation failed/, fn ->
        Config.resolve_config!(PluginWithConfigSchema, %{})
      end
    end
  end

  describe "get_app_env_config/1" do
    test "returns empty map when no otp_app" do
      assert Config.get_app_env_config(PluginWithoutOtpApp) == %{}
    end

    test "returns empty map when otp_app config not set" do
      assert Config.get_app_env_config(PluginWithOtpApp) == %{}
    end

    test "returns config from app env" do
      Application.put_env(:jido, PluginWithOtpApp, foo: "bar")

      on_exit(fn ->
        Application.delete_env(:jido, PluginWithOtpApp)
      end)

      config = Config.get_app_env_config(PluginWithOtpApp)
      assert config[:foo] == "bar"
    end
  end
end
