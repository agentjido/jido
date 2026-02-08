defmodule JidoTest.Igniter.HelpersTest do
  use ExUnit.Case, async: true

  alias Jido.Igniter.Helpers

  describe "module_to_name/1" do
    test "converts module atoms to snake_case terminal name" do
      assert Helpers.module_to_name(MyApp.Agents.Coordinator) == "coordinator"
    end

    test "converts module strings to snake_case terminal name" do
      assert Helpers.module_to_name("MyApp.Agents.Coordinator") == "coordinator"
    end
  end

  describe "parse_list/1" do
    test "returns empty list for nil" do
      assert Helpers.parse_list(nil) == []
    end

    test "splits comma-separated list and trims blanks" do
      assert Helpers.parse_list("alpha, beta,, gamma  ,  ") == ["alpha", "beta", "gamma"]
    end
  end
end
