defmodule JidoTest.Igniter.TemplatesTest do
  use ExUnit.Case, async: true

  alias Jido.Igniter.Templates

  describe "agent_template/3" do
    test "includes optional plugins list when provided" do
      template =
        Templates.agent_template(
          "MyApp.Agent",
          "my_agent",
          plugins: [MyApp.PluginOne, MyApp.PluginTwo]
        )

      assert template =~ "plugins: [MyApp.PluginOne, MyApp.PluginTwo]"
    end
  end

  describe "agent_test_template/2" do
    test "uses module alias name in assertions" do
      template = Templates.agent_test_template("MyApp.Agents.Example", "JidoTest.Agents.Example")

      assert template =~ "agent = Example.new()"
      assert template =~ "assert agent.name == Example.name()"
    end
  end
end
