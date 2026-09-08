defmodule JidoTest.Topology.AuthoringHostTest do
  use JidoTest.Case, async: false

  alias Jido.Agent
  alias Jido.AgentServer
  alias Jido.Topology.Instance

  defmodule Label do
    defstruct [:key, :value, :__spark_metadata__]
  end

  defmodule AgentLabels do
    @label %Spark.Dsl.Entity{
      name: :label,
      target: Label,
      args: [:key, :value],
      schema: [key: [type: :atom, required: true], value: [type: :any, required: true]]
    }

    use Spark.Dsl.Extension,
      dsl_patches: [%Spark.Dsl.Patch.AddEntity{section_path: [:agent], entity: @label}]

    @behaviour Jido.Agent.Extension

    @impl Jido.Agent.Extension
    def lower_agent(config, entities) do
      {labels, rest} = Enum.split_with(entities, &match?(%Label{}, &1))
      metadata = Enum.reduce(labels, config.metadata, &Map.put(&2, &1.key, &1.value))
      {:ok, %{config | metadata: metadata}, rest}
    end
  end

  defmodule Role do
    defstruct [:key, :module, :__spark_metadata__]
  end

  defmodule TopologyRoles do
    @role %Spark.Dsl.Entity{
      name: :role,
      target: Role,
      args: [:key, :module],
      schema: [
        key: [type: :atom, required: true],
        module: [type: :atom, required: true]
      ]
    }

    use Spark.Dsl.Extension,
      dsl_patches: [
        %Spark.Dsl.Patch.AddEntity{section_path: [:topology, :agents], entity: @role}
      ]

    @behaviour Jido.Topology.Extension

    @impl Jido.Topology.Extension
    def lower_topology(config, entities) do
      {roles, rest} = Enum.split_with(entities, &match?(%Role{}, &1))

      agents =
        Enum.reduce(roles, config.agents, fn role, agents ->
          agents ++ [%{key: role.key, module: role.module}]
        end)

      {:ok, %{config | agents: agents}, rest}
    end
  end

  defmodule Add do
    use Jido.Action,
      name: "topology_owner_add",
      schema: Zoi.object(%{amount: Zoi.integer()})

    @impl Jido.Action
    def run(%{amount: amount}, %{agent_state: state}) do
      {:ok, %{state | count: state.count + amount}}
    end
  end

  test "one host composes Agent and Topology DSLs and keeps constructor meanings", %{jido: jido} do
    module = Module.concat(__MODULE__, "Combined#{System.unique_integer([:positive])}")

    compile_isolated(
      quote do
        defmodule unquote(module) do
          use Jido.Topology,
            name: "combined_topology",
            extensions: [AgentLabels, TopologyRoles]

          agent do
            schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
            label(:kind, :owner)
          end

          routes do
            signal_source "/topology-owner"

            route "owner.add", Add do
              define :add, args: [:amount]
            end
          end

          topology do
            agents do
              agent :worker, Jido.Examples.Topology.Cell
              role(:observer, Jido.Examples.Topology.Cell)
            end

            resources do
              bus :events
            end

            connections do
              subscribe :worker, to: :events, path: "owner.**"
            end

            startup do
              concurrency 2
            end
          end
        end
      end
    )

    owner = module.agent()
    assert %Agent{module: ^module, name: "combined_topology"} = owner
    assert owner.metadata == %{kind: :owner}
    assert [%{path: "owner.add", target: Add}] = owner.routes

    topology = module.topology()
    assert Enum.map(topology.agents, & &1.key) == ["worker", "observer"]
    assert [%{key: "events"}] = topology.resources
    assert topology.startup.concurrency == 2

    assert {:ok, %Instance{id: topology_id}} = module.new(id: "combined-instance")
    assert topology_id == "combined-instance"

    assert {:ok, %Agent{id: "owner-instance", module: ^module}} =
             module.new_agent(id: "owner-instance")

    assert {:ok, server} = Jido.start_agent(jido, module, id: "live-owner")
    assert AgentServer.agent(server).module == module
    assert {:ok, %{state: %{count: 3}}} = module.add(server, 3)
  end

  test "a topology without an agent block gets a neutral default owner" do
    module = Module.concat(__MODULE__, "Default#{System.unique_integer([:positive])}")

    compile_isolated(
      quote do
        defmodule unquote(module) do
          use Jido.Topology, name: "default_owner"

          topology do
            agents do
              agent :worker, Jido.Examples.Topology.Cell
            end
          end
        end
      end
    )

    assert %Agent{
             module: ^module,
             name: "default_owner",
             plugins: [],
             routes: [],
             metadata: %{}
           } = module.agent()

    assert {:ok, %Agent{state: %{}}} = module.new_agent(id: "default-owner")
    assert {:ok, %Instance{}} = module.new(id: "default-topology")
  end

  test "module attribute options keep the combined authoring host" do
    module = Module.concat(__MODULE__, "AttributeOptions#{System.unique_integer([:positive])}")

    compile_isolated(
      quote do
        defmodule unquote(module) do
          @options [name: "attribute_options"]
          use Jido.Topology, @options

          topology do
            agents do
              agent :worker, Jido.Examples.Topology.Cell
            end
          end
        end
      end
    )

    assert %Agent{name: "attribute_options"} = module.agent()
    assert Enum.map(module.topology().agents, & &1.key) == ["worker"]
  end

  test "map options keep the combined authoring host" do
    module = Module.concat(__MODULE__, "MapOptions#{System.unique_integer([:positive])}")

    compile_isolated(
      quote do
        defmodule unquote(module) do
          use Jido.Topology, %{
            name: "map_options",
            description: "Topology owner"
          }

          topology do
            resources do
              bus :events
            end
          end
        end
      end
    )

    assert %Agent{
             name: "map_options",
             description: "Topology owner"
           } = module.agent()

    assert [%{key: "events"}] = module.topology().resources
  end

  test "one topology section cannot be split between legacy and nested locations" do
    module = Module.concat(__MODULE__, "Split#{System.unique_integer([:positive])}")

    assert_raise CompileError,
                 ~r/Topology section :agents cannot be declared in both locations/,
                 fn ->
                   compile_isolated(
                     quote do
                       defmodule unquote(module) do
                         use Jido.Topology, name: "split_agents"

                         agents do
                           agent :legacy, Jido.Examples.Topology.Cell
                         end

                         topology do
                           agents do
                             agent :nested, Jido.Examples.Topology.Cell
                           end
                         end
                       end
                     end
                   )
                 end
  end

  test "startup cannot be split between legacy and nested locations" do
    module = Module.concat(__MODULE__, "SplitStartup#{System.unique_integer([:positive])}")

    assert_raise CompileError,
                 ~r/Topology section :startup cannot be declared in both locations/,
                 fn ->
                   compile_isolated(
                     quote do
                       defmodule unquote(module) do
                         use Jido.Topology, name: "split_startup"

                         startup do
                           concurrency 1
                         end

                         topology do
                           startup do
                             concurrency 2
                           end
                         end
                       end
                     end
                   )
                 end
  end

  defp compile_isolated(ast) do
    owner = self()

    {pid, ref} =
      spawn_monitor(fn -> send(owner, {self(), :compiled, Code.compile_quoted(ast)}) end)

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        receive do
          {^pid, :compiled, result} -> result
        end

      {:DOWN, ^ref, :process, ^pid, {error, stack}} ->
        reraise error, stack
    after
      10_000 ->
        Process.exit(pid, :kill)
        flunk("Topology compilation did not finish")
    end
  end
end
