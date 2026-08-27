defmodule Jido.Agent.BoundaryValidationTest do
  use ExUnit.Case, async: true

  alias Jido.Agent

  defmodule RouteMatches do
    def matches?(_signal), do: true
  end

  defmodule SchemaRefinements do
    def nonempty(value), do: if(value == "", do: {:error, "must not be empty"}, else: :ok)
  end

  test "structural validation accepts definitions and complete instances" do
    definition = Agent.new!(name: "lifecycle_agent")
    assert {:ok, ^definition} = Agent.validate(definition)

    instance = %{definition | id: "instance-1", state: %{}, agent_module: __MODULE__}
    assert {:ok, ^instance} = Agent.validate(instance)
    assert Agent.definition(instance) == definition
  end

  test "structural validation rejects both half-instance forms with a lifecycle path" do
    definition = Agent.new!(name: "half_instance_agent")

    for {invalid, path} <- [
          {%{definition | id: "instance-1"}, [:state]},
          {%{definition | state: %{}}, [:id]},
          {%{definition | id: "", state: %{}}, [:id]},
          {%{definition | agent_module: __MODULE__}, [:agent_module]}
        ] do
      assert {:error, error} = Agent.validate(invalid)
      assert Exception.message(error) == "agent runtime fields form an invalid lifecycle state"
      assert error.details.path == path
      assert error.details.lifecycle == :half_instance
    end
  end

  test "root and nested records are closed and validate their field types" do
    for attrs <- [
          :bad,
          [:not_keyword],
          %{name: "agent", unexpected: true},
          %{name: 1},
          %{name: "agent", description: <<255>>},
          %{name: "agent", metadata: []},
          %{name: "agent", plugins: :bad},
          %{name: "agent", schedules: :bad},
          %{name: "agent", extensions: :bad}
        ] do
      assert {:error, error} = Agent.new(attrs)
      assert is_exception(error)
    end

    assert_raise Jido.Error.ValidationError, fn -> Agent.new!(name: "agent", unexpected: true) end
  end

  test "state schemas use the static Action schema rules" do
    schema =
      Zoi.object(%{
        value: Zoi.string() |> Zoi.refine({SchemaRefinements, :nonempty, []})
      })

    assert %Agent{state_schema: ^schema} =
             Agent.new!(name: "static_schema_agent", state_schema: schema)

    invalid_schemas = [
      Zoi.object(%{value: Zoi.lazy(fn -> Zoi.string() end)}),
      Zoi.object(%{value: Zoi.string() |> Zoi.refine(fn _ -> :ok end)}),
      fn -> :bad end,
      [self()],
      [:ok | :tail]
    ]

    for invalid_schema <- invalid_schemas do
      assert {:error, error} =
               Agent.new(name: "unsafe_schema_agent", state_schema: invalid_schema)

      assert Exception.message(error) =~ "state_schema must be static module data"
    end
  end

  test "routes accept stable external unary captures and reject local functions and closures" do
    external = &RouteMatches.matches?/1

    assert %Agent{routes: [%Jido.Signal.Router.Route{match: ^external}]} =
             Agent.new!(
               name: "external_route_agent",
               routes: [{"event.received", external, RouteMatches}]
             )

    local = &local_match/1
    captured = :value
    closure = fn _signal -> captured == :value end

    for invalid_match <- [local, closure, fn _signal -> true end] do
      assert {:error, error} =
               Agent.new(
                 name: "unsafe_route_agent",
                 routes: [{"event.received", invalid_match, RouteMatches}]
               )

      assert Exception.message(error) ==
               "agent route matches must be stable external unary function captures"
    end
  end

  test "route static parameters use the Agent data grammar" do
    assert %Agent{routes: [%Jido.Signal.Router.Route{target: {RouteMatches, %{count: 1}}}]} =
             Agent.new!(
               name: "static_route_agent",
               routes: [{"event.received", RouteMatches, %{count: 1}}]
             )

    assert {:error, error} =
             Agent.new(
               name: "unsafe_static_route_agent",
               routes: [{"event.received", RouteMatches, %{pid: self()}}]
             )

    assert Exception.message(error) == "agent data contains an unsupported value"
    assert error.details.path == [:routes, 0, :target, 1, :pid]
  end

  defp local_match(_signal), do: true
end
