Code.require_file("support/jido_agent/composable_fixtures.exs", __DIR__)
Code.require_file("support/jido_agent/composable_compiler.exs", __DIR__)
Code.require_file("support/jido_flow/components.ex", __DIR__)

defmodule Jido.Authoring.RejectionEquivalenceTest do
  use ExUnit.Case, async: false
  @moduletag :authoring

  alias Jido.Agent
  alias Jido.Flow.Ref
  alias Jido.Test.Agent.Authoring.{Action, Compiler}
  alias Jido.Test.Flow.Authoring.Components.Echo
  alias Jido.Test.Flow.Codec

  test "Agent DSL, Map, and JSON reject the same duplicate route" do
    route = %{
      path: "work.request",
      handler: %{kind: :action, target: Action},
      state: %{source: :output, path: []}
    }

    assert {:error, map_error} =
             Agent.define(%{name: "duplicate", routes: [route, route]})

    assert map_error.path != []

    error =
      assert_raise Spark.Error.DslError, fn ->
        Compiler.compile(
          ~s|routes do route "work.request", #{inspect(Action)}; route "work.request", #{inspect(Action)} end|,
          ~s|name: "duplicate"|
        )
      end

    assert Exception.message(error) =~ "Duplicate declaration"

    valid = Agent.define!(%{name: "duplicate", routes: [route]})
    catalog = Jido.Test.AgentServer.Registry.for(valid)
    assert {:ok, document} = Jido.Test.AgentServer.Registry.encode(valid, catalog)
    [stored_route] = document["definition"]["routes"]
    invalid = put_in(document, ["definition", "routes"], [stored_route, stored_route])
    assert {:error, _} = Jido.Test.AgentServer.Registry.decode(invalid, catalog)
  end

  test "Flow DSL, Map, and JSON reject the same duplicate component" do
    component = %{
      kind: :step,
      name: "work",
      action: Echo,
      params: %{value: Ref.input(:value)}
    }

    data = %{
      name: "duplicate_flow",
      components: [component, component],
      output: Ref.result("work")
    }

    assert {:error, %{message: "duplicate component name"}} =
             Jido.Test.Flow.Builder.new(data)

    module = Module.concat(__MODULE__, "Duplicate#{System.unique_integer([:positive])}")

    source = """
    defmodule #{inspect(module)} do
      use Jido.Flow, name: "duplicate_flow"
      flow do
        step "work", action: #{inspect(Echo)}, params: %{value: input(:value)}
        step "work", action: #{inspect(Echo)}, params: %{value: input(:value)}
        output result("work")
      end
    end
    """

    assert_raise CompileError, ~r/duplicate Step name/, fn ->
      Code.compile_string(source, "duplicate_flow.ex")
    end

    valid = Jido.Test.Flow.Builder.new!(%{data | components: [component]})
    assert {:ok, document, catalog} = Codec.encode(valid)
    [stored_component] = document["components"]
    invalid = put_in(document, ["components"], [stored_component, stored_component])
    assert {:error, %{message: "duplicate component name"}} = Codec.decode(invalid, catalog)
  end
end
