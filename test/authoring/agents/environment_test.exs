defmodule JidoTest.Authoring.Agents.EnvironmentTest do
  use ExUnit.Case, async: false
  @moduletag :authoring

  alias Jido.Agent

  defmodule Settings do
    @section %Spark.Dsl.Section{
      name: :settings,
      schema: [values: [type: :any, required: true]]
    }
    use Jido.Agent.Extension, id: "test.environment", sections: [@section]

    def lower(dsl, _config),
      do: {:ok, Spark.Dsl.Extension.get_opt(dsl, [:settings], :values)}
  end

  test "the DSL compiles without a variable and matches Map authoring" do
    name = "JIDO_AUTHORING_ENV_#{System.unique_integer([:positive])}"
    module = Module.concat(__MODULE__, "Host#{System.unique_integer([:positive])}")

    on_exit(fn ->
      System.delete_env(name)
      :code.purge(module)
      :code.delete(module)
    end)

    assert System.fetch_env(name) == :error

    Code.compile_string("""
    defmodule #{inspect(module)} do
      use Jido.Agent, name: "environment", extensions: [#{inspect(Settings)}]

      settings do
        values %{credentials: %{token: env(#{inspect(name)})}, rooms: [env(#{inspect(name)})]}
      end
    end
    """)

    data = %{credentials: %{token: Jido.Config.env(name)}, rooms: [Jido.Config.env(name)]}

    definition =
      Agent.define!(%{
        name: "environment",
        module: module,
        extensions: [%{id: Settings.id(), provider: Settings, vsn: 1, data: data}]
      })

    assert module.definition() === definition

    for expected <- ["first", "second"] do
      System.put_env(name, expected)
      assert module.definition() === definition

      assert Jido.Config.resolve(hd(definition.extensions).data) ==
               {:ok, %{credentials: %{token: expected}, rooms: [expected]}}
    end

    agent = Agent.instantiate!(definition, id: "environment-agent")

    assert {:error, %Jido.Authoring.Error.InvalidError{code: :value}} =
             JidoTest.AgentRegistry.encode(agent, JidoTest.AgentRegistry.for(agent))

    assert {:ok, snapshot} = Jido.Persistence.snapshot(agent)
    System.delete_env(name)
    assert {:ok, ^agent} = Jido.Persistence.restore(snapshot)
    assert agent.state == %{}
    refute inspect(snapshot) =~ "second"
  end
end
