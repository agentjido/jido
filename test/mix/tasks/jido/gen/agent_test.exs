if Code.ensure_loaded?(Mix.Tasks.Jido.Gen.Agent) do
  defmodule Mix.Tasks.Jido.Gen.AgentTest do
    use ExUnit.Case, async: true

    describe "normalize_plugin_modules!/1" do
      test "returns validated module names as strings" do
        assert [
                 "MyApp.Plugins.Chat",
                 "MyApp.Plugins.Support"
               ] =
                 Mix.Tasks.Jido.Gen.Agent.normalize_plugin_modules!(
                   "MyApp.Plugins.Chat,MyApp.Plugins.Support"
                 )
      end

      test "rejects invalid module names" do
        assert_raise ArgumentError, ~r/invalid plugin module name/i, fn ->
          Mix.Tasks.Jido.Gen.Agent.normalize_plugin_modules!("bad-plugin-name")
        end
      end
    end
  end
end
