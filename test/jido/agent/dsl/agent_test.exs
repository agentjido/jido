defmodule Jido.Agent.DSL.AgentTest.RouteMatches do
  @moduledoc false

  def important?(signal), do: signal.data[:important] == true
end

defmodule Jido.Agent.DSL.AgentTest.SparkAgent do
  @moduledoc false

  use Jido.Agent,
    name: "spark_agent",
    description: "A Spark Agent"

  agent do
    state_schema(
      Zoi.object(%{
        count: Zoi.integer() |> Zoi.default(0)
      })
    )

    route("agent.important", JidoTest.TestActions.NoSchema,
      match: &Jido.Agent.DSL.AgentTest.RouteMatches.important?/1,
      params: %{source: "dsl"},
      priority: 5
    )

    schedule("heartbeat", "*/5 * * * *", "agent.important", data: %{source: "dsl"})
  end
end

defmodule Jido.Agent.DSL.AgentTest.ExtraExtension do
  @moduledoc false

  @extra %Spark.Dsl.Section{
    name: :extra,
    schema: [enabled: [type: :boolean, default: true]]
  }

  use Spark.Dsl.Extension, sections: [@extra]
end

defmodule Jido.Agent.DSL.AgentTest.ExtensionOnlyAgent do
  @moduledoc false

  use Jido.Agent,
    name: "extension_only_agent",
    extensions: [Jido.Agent.DSL.AgentTest.ExtraExtension]

  extra do
    enabled(false)
  end
end

defmodule Jido.Agent.DSL.AgentTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.DSL.AgentTest.SparkAgent
  alias Jido.Signal.Router.Route

  test "Spark declarations lower to one neutral canonical Agent" do
    match = &Jido.Agent.DSL.AgentTest.RouteMatches.important?/1

    assert %Agent{
             id: nil,
             state: nil,
             agent_module: nil,
             name: "spark_agent",
             description: "A Spark Agent",
             routes: [
               %Route{
                 path: "agent.important",
                 target: {JidoTest.TestActions.NoSchema, %{source: "dsl"}},
                 match: ^match,
                 priority: 5
               }
             ],
             schedules: [%Agent.Schedule{name: "heartbeat", data: %{source: "dsl"}}]
           } = SparkAgent.agent()

    assert SparkAgent.definition() == SparkAgent.agent()
    assert SparkAgent.name() == "spark_agent"
    assert SparkAgent.description() == "A Spark Agent"
    assert SparkAgent.schema() == SparkAgent.compiled().state_schema
  end

  test "new/1 creates an instance and keeps the command API" do
    instance = SparkAgent.new(id: "spark-1", state: %{count: 2})

    assert %Agent{id: "spark-1", state: %{count: 2}, agent_module: SparkAgent} = instance
    assert function_exported?(SparkAgent, :cmd, 2)
    assert function_exported?(SparkAgent, :cmd, 3)
  end

  test "source locations stay outside canonical Agent data" do
    source_map = SparkAgent.__jido_agent_source_map__()
    agent = SparkAgent.agent()

    refute Map.has_key?(Map.from_struct(agent), :source_map)
    assert %{file: file, line: line} = source_map[[:routes, 0]]
    assert is_binary(file)
    assert is_integer(line)
    assert source_map[[:schedules, 0]].file == file
  end

  test "an extension-only Agent does not need an empty agent block" do
    module = Jido.Agent.DSL.AgentTest.ExtensionOnlyAgent

    assert %Agent{name: "extension_only_agent"} = module.agent()
    assert Spark.Dsl.Extension.get_opt(module, [:extra], :enabled) == false
  end

  test "a state schema expression is evaluated once" do
    counter = Module.concat(__MODULE__, "SchemaCounter#{System.unique_integer([:positive])}")
    agent = Module.concat(__MODULE__, "SchemaAgent#{System.unique_integer([:positive])}")
    test_pid = self()

    Code.compile_quoted(
      quote do
        defmodule unquote(counter) do
          def schema do
            send(unquote(test_pid), :schema_evaluated)
            Zoi.object(%{value: Zoi.string()})
          end
        end

        defmodule unquote(agent) do
          use Jido.Agent, name: "schema_once_agent"

          agent do
            state_schema(unquote(counter).schema())
          end
        end
      end
    )

    assert_receive :schema_evaluated
    refute_receive :schema_evaluated
    assert %Zoi.Types.Map{} = agent.schema()
  end

  test "anonymous and lazy state schemas fail during compilation" do
    anonymous = """
    defmodule AnonymousSparkSchemaAgent do
      use Jido.Agent, name: "anonymous_spark_schema_agent"

      agent do
        state_schema Zoi.object(%{value: Zoi.string() |> Zoi.refine(fn _ -> :ok end)})
      end
    end
    """

    lazy = """
    defmodule LazySparkSchemaAgent do
      use Jido.Agent, name: "lazy_spark_schema_agent"

      agent do
        state_schema Zoi.object(%{value: Zoi.lazy(fn -> Zoi.string() end)})
      end
    end
    """

    assert_raise CompileError, ~r/anonymous functions are not supported/, fn ->
      Code.compile_string(anonymous)
    end

    assert_raise CompileError, ~r/lazy schemas are not supported/, fn ->
      Code.compile_string(lazy)
    end
  end

  test "route closures fail and named external captures work" do
    closure = """
    defmodule ClosureSparkRouteAgent do
      value = true
      use Jido.Agent, name: "closure_spark_route_agent"

      agent do
        route "event.received", JidoTest.TestActions.NoSchema,
          match: fn _signal -> value end
      end
    end
    """

    assert_raise CompileError,
                 ~r/agent route matches must be stable external unary function captures/,
                 fn -> Code.compile_string(closure) end

    assert is_function(hd(SparkAgent.agent().routes).match, 1)
  end
end
