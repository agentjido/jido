defmodule Jido.Agent.BuilderTest do
  use JidoTest.Case, async: true
  alias Jido.Agent.Builder

  defmodule CheckedTarget do
    def __jido_executable__ do
      send(self(), :target_checked)

      if Process.get(:reject_builder_target),
        do: :invalid,
        else: Jido.Executable.action(__MODULE__)
    end

    def validate_params(value), do: {:ok, value}
    def validate_output(value), do: {:ok, value}
    def run(_input, _context), do: raise("authoring must not execute Actions")
  end

  test "appending routes checks each new target and build checks the complete definition" do
    builder =
      Enum.reduce(1..3, Builder.new(name: "checked"), fn index, builder ->
        Builder.route(builder, "checked.route#{index}", CheckedTarget)
      end)

    for _ <- 1..3, do: assert_received(:target_checked)
    refute_received :target_checked
    assert {:ok, definition} = Builder.build(builder)

    assert Enum.map(definition.routes, & &1.path) == [
             "checked.route1",
             "checked.route2",
             "checked.route3"
           ]

    for _ <- 1..3, do: assert_received(:target_checked)
    refute_received :target_checked

    Process.put(:reject_builder_target, true)
    assert {:error, %{message: "Invalid Agent route executable"}} = Builder.build(builder)
    assert_received :target_checked
    refute_received :target_checked
  end

  test "bulk routes and appended routes retain order and builder values can be reused" do
    target = JidoTest.AgentFixtures.Add
    first = Builder.new(name: "ordered", routes: [{"first", target, defaults: %{by: 1}}])
    second = Builder.route(first, "second", target, priority: 2)
    third = Builder.route(second, "third", target, defaults: %{by: 3})

    assert {:ok, %{routes: [%{path: "first", target: {^target, %{by: 1}}}]}} =
             Builder.build(first)

    assert Enum.map(Builder.build!(second).routes, & &1.path) == ["first", "second"]
    assert Enum.map(Builder.build!(third).routes, & &1.path) == ["first", "second", "third"]
    assert Enum.map(Builder.build!(third).routes, & &1.priority) == [0, 2, 0]
  end

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
