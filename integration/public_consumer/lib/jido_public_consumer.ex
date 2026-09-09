defmodule JidoPublicConsumer.AgentFacet do
  @moduledoc false
  use Jido.Agent.Plugin

  def state_spec(_opts), do: {:plugin_count, Zoi.integer() |> Zoi.default(0)}
end

defmodule JidoPublicConsumer.ServerFacet do
  @moduledoc false
  use Jido.AgentServer.Plugin

  def admit(_runtime, command, _opts), do: {:ok, command}
end

defmodule JidoPublicConsumer.PersistenceFacet do
  @moduledoc false
  use Jido.Persistence.Plugin

  def dump(value, _context, _opts), do: {:ok, value}
  def load(value, _context, _opts), do: {:ok, value}
end

defmodule JidoPublicConsumer.TopologyFacet do
  @moduledoc false
  use Jido.Topology.Plugin

  alias Jido.Topology.Plugin.Contribution

  def contribute(context, _opts) do
    {:ok,
     %Contribution{
       plugin: context.plugin,
       resources: [%{key: "inbox", config: []}],
       connections: [%{agent: context.agent_key, to: "inbox", path: "consumer.**"}]
     }}
  end
end

defmodule JidoPublicConsumer.Plugin do
  @moduledoc false
  use Jido.Plugin,
    agent: JidoPublicConsumer.AgentFacet,
    agent_server: JidoPublicConsumer.ServerFacet,
    persistence: JidoPublicConsumer.PersistenceFacet,
    topology: JidoPublicConsumer.TopologyFacet,
    vsn: 1
end

defmodule JidoPublicConsumer.Agent do
  @moduledoc false
  use Jido.Agent,
    name: "jido_public_consumer_agent",
    plugins: [JidoPublicConsumer.Plugin]

  agent do
    schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
  end
end

defmodule JidoPublicConsumer.Topology do
  @moduledoc false
  use Jido.Topology, name: "jido_public_consumer_topology"

  agents do
    agent(:worker, JidoPublicConsumer.Agent)
  end
end
