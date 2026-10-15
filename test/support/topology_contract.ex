defmodule JidoTest.TopologyContract do
  @moduledoc false

  alias JidoTest.AgentContract, as: A

  def with_topology(body, callback, options \\ "name: \"contract_topology\"", before_use \\ "") do
    module = Module.concat(__MODULE__, "Fixture#{System.unique_integer([:positive])}")

    source = """
    defmodule #{inspect(module)} do
      alias JidoTest.AgentContract, as: A, warn: false
      alias JidoTest.TopologyContract, as: T, warn: false
      #{before_use}
      use Jido.Topology, #{options}
      #{body}
    end
    """

    JidoTest.AuthoringCompiler.with_compiled(source, fn _ -> callback.(module) end,
      modules: [module]
    )
  end

  def worker(plugins \\ []) do
    Jido.Agent.new!(
      name: "worker",
      schema:
        Zoi.object(%{
          count: Zoi.integer() |> Zoi.default(0),
          enabled: Zoi.boolean() |> Zoi.default(true),
          label: Zoi.string() |> Zoi.default("worker")
        }),
      plugins: plugins
    )
  end

  defmodule Role do
    defstruct [:key, :definition, :__spark_metadata__]
  end

  defmodule Roles do
    @role %Spark.Dsl.Entity{
      name: :role,
      target: Role,
      args: [:key, :definition],
      schema: [key: [type: :atom, required: true], definition: [type: :any, required: true]]
    }
    use Spark.Dsl.Extension,
      dsl_patches: [
        %Spark.Dsl.Patch.AddEntity{section_path: [:topology, :agents], entity: @role}
      ]

    def lower_topology(config, entities) do
      A.observe({:lowered, :roles})
      {roles, rest} = Enum.split_with(entities, &match?(%Role{}, &1))
      agents = config.agents ++ Enum.map(roles, &%{key: &1.key, definition: &1.definition})
      {:ok, %{config | agents: agents, metadata: %{order: [:roles]}}, rest}
    end
  end

  defmodule Dual do
    use Spark.Dsl.Extension

    def lower_agent(config, entities) do
      A.observe({:lowered, :agent_dual})
      {:ok, %{config | metadata: Map.put(config.metadata, :dual, true)}, entities}
    end

    def lower_topology(config, entities) do
      A.observe({:lowered, :topology_dual})

      {:ok, %{config | metadata: Map.update!(config.metadata, :order, &(&1 ++ [:dual]))},
       entities}
    end
  end

  defmodule Unclaimed do
    use Spark.Dsl.Extension, dsl_patches: Roles.dsl_patches()
    def lower_topology(config, entities), do: {:ok, config, entities}
  end

  defmodule InvalidLowering do
    use Spark.Dsl.Extension
    def lower_topology(config, entities), do: {:ok, Map.put(config, :unknown, true), entities}
  end

  defmodule Bus do
    use Jido.Plugin, option_keys: [topology: [:prefix, :mode]]
    defdelegate contribute(context, opts), to: JidoTest.TopologyContract
  end

  defmodule Audit do
    use Jido.Plugin, option_keys: [topology: [:prefix, :mode]]
    defdelegate contribute(context, opts), to: JidoTest.TopologyContract
  end

  def contribute(context, opts) do
    send(self(), {:contributed, context.plugin, context.agent_key})
    key = Keyword.get(opts, :prefix, "bus_") <> context.agent_key

    contribution = %Jido.Topology.Plugin.Contribution{
      plugin: context.plugin,
      resources: [%{key: key}],
      connections: [%{agent: context.agent_key, to: key, path: "contract.**"}]
    }

    case opts[:mode] do
      :reject -> {:error, :application_rejection}
      :raise -> raise ArgumentError, "contribution failure"
      :throw -> throw(:contribution_failure)
      :exit -> exit(:contribution_failure)
      :invalid -> :invalid
      :owner -> {:ok, %{contribution | plugin: Enum}}
      :entries -> {:ok, %{contribution | resources: [%{key: key, kind: :unknown}]}}
      :improper -> {:ok, %{contribution | resources: Process.get(:topology_contract_entries)}}
      _ -> {:ok, contribution}
    end
  end
end
