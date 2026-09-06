defmodule Jido.Agent.BuilderValidationTest do
  use JidoTest.Case, async: true
  alias Jido.Agent.Builder

  test "Builder preserves its first field error through later operations" do
    for {attrs, message} <- [
          {[description: 42], "Agent description must be a string or nil"},
          {[metadata: ~D[2026-09-05]], "Agent metadata must be a plain map"},
          {[name: "invalid name"], "name must start with a letter"}
        ] do
      builder = Builder.new(attrs)
      assert {:error, error} = Builder.build(builder)
      assert error.message =~ message

      next =
        builder
        |> Builder.route("valid.event", JidoTest.AgentFixtures.Add)
        |> Builder.plugin(Jido.Plugin.SensorManager)

      assert Builder.build(next) == {:error, error}
    end

    builder = Builder.new(name: "valid") |> Builder.plugin(String)
    assert {:error, error} = Builder.build(builder)
    assert error.message == "Agent Plugin must use Jido.Plugin"
    valid = Builder.new(name: "valid")
    assert {:ok, ^valid} = Zoi.parse(Builder.schema(), valid)
  end
end
