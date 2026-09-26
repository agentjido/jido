defmodule Jido.Plugin.Spec do
  @moduledoc false

  @enforce_keys [:module, :options]
  defstruct module: nil,
            options: [],
            manifest: nil,
            agent: nil,
            agent_server: nil,
            persistence: nil,
            topology: nil

  @type t :: %__MODULE__{
          module: module(),
          options: keyword(),
          manifest: Jido.Plugin.Manifest.t(),
          agent: Jido.Agent.Plugin.Spec.t() | nil,
          agent_server: Jido.AgentServer.Plugin.Spec.t() | nil,
          persistence: Jido.Persistence.Plugin.Spec.t() | nil,
          topology: Jido.Topology.Plugin.Spec.t() | nil
        }
end
