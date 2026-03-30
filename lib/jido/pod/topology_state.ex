defmodule Jido.Pod.TopologyState do
  @moduledoc false

  alias Jido.Agent
  alias Jido.AgentServer
  alias Jido.AgentServer.State
  alias Jido.Plugin.Instance, as: PluginInstance
  alias Jido.Pod.Plugin
  alias Jido.Pod.Topology

  @pod_state_key Plugin.state_key_atom()

  @spec pod_plugin_instance(module()) :: {:ok, PluginInstance.t()} | {:error, term()}
  def pod_plugin_instance(agent_module) when is_atom(agent_module) do
    instances =
      if function_exported?(agent_module, :plugin_instances, 0) do
        agent_module.plugin_instances()
      else
        []
      end

    case Enum.find(instances, &(&1.state_key == @pod_state_key)) do
      %PluginInstance{} = instance ->
        {:ok, instance}

      nil ->
        {:error,
         Jido.Error.validation_error(
           "#{inspect(agent_module)} is missing the reserved #{@pod_state_key} plugin instance."
         )}
    end
  end

  @spec fetch_state(Agent.t() | State.t()) :: {:ok, map()} | {:error, term()}
  def fetch_state(%State{agent: agent}), do: fetch_state(agent)

  def fetch_state(%Agent{agent_module: agent_module, state: state}) when is_map(state) do
    with {:ok, instance} <- pod_plugin_instance(agent_module) do
      case Map.get(state, instance.state_key) do
        plugin_state when is_map(plugin_state) ->
          {:ok, plugin_state}

        other ->
          {:error,
           Jido.Error.validation_error(
             "Pod plugin state is missing or malformed.",
             details: %{state_key: instance.state_key, value: other}
           )}
      end
    end
  end

  def fetch_state(agent) do
    {:error,
     Jido.Error.validation_error(
       "Expected an agent or AgentServer state when fetching pod state.",
       details: %{agent: agent}
     )}
  end

  @spec fetch_topology(module() | Agent.t() | State.t() | AgentServer.server()) ::
          {:ok, Topology.t()} | {:error, term()}
  def fetch_topology(module) when is_atom(module) do
    if function_exported?(module, :topology, 0) do
      {:ok, module.topology()}
    else
      with {:ok, state} <- AgentServer.state(module) do
        fetch_topology(state)
      end
    end
  end

  def fetch_topology(%State{agent: agent}), do: fetch_topology(agent)

  def fetch_topology(%Agent{} = agent) do
    with {:ok, plugin_state} <- fetch_state(agent) do
      extract_topology(plugin_state)
    end
  end

  def fetch_topology(server) do
    with {:ok, state} <- AgentServer.state(server) do
      fetch_topology(state)
    end
  end

  @spec put_topology(Agent.t(), Topology.t()) :: {:ok, Agent.t()} | {:error, term()}
  def put_topology(%Agent{} = agent, %Topology{} = topology) do
    with {:ok, current_topology} <- fetch_topology(agent),
         {:ok, instance} <- pod_plugin_instance(agent.agent_module),
         {:ok, pod_state} <- fetch_state(agent) do
      normalized_topology = normalize_updated_topology(current_topology, topology)
      {:ok, persist_topology(agent, instance.state_key, pod_state, normalized_topology)}
    end
  end

  @spec update_topology(
          Agent.t(),
          (Topology.t() -> Topology.t() | {:ok, Topology.t()} | {:error, term()})
        ) ::
          {:ok, Agent.t()} | {:error, term()}
  def update_topology(%Agent{} = agent, fun) when is_function(fun, 1) do
    with {:ok, topology} <- fetch_topology(agent),
         {:ok, new_topology} <- normalize_topology_update(fun.(topology)),
         {:ok, instance} <- pod_plugin_instance(agent.agent_module),
         {:ok, pod_state} <- fetch_state(agent) do
      normalized_topology = normalize_updated_topology(topology, new_topology)
      {:ok, persist_topology(agent, instance.state_key, pod_state, normalized_topology)}
    end
  end

  @doc false
  @spec normalize_updated_topology(Topology.t(), Topology.t()) :: Topology.t()
  def normalize_updated_topology(%Topology{} = current, %Topology{} = updated) do
    if topology_changed?(current, updated) do
      %{updated | version: max(updated.version, current.version + 1)}
    else
      %{updated | version: current.version}
    end
  end

  defp extract_topology(%{topology: %Topology{} = topology}), do: {:ok, topology}

  defp extract_topology(plugin_state) do
    {:error,
     Jido.Error.validation_error(
       "Pod plugin state does not contain a valid topology snapshot.",
       details: %{state: plugin_state}
     )}
  end

  defp normalize_topology_update({:ok, %Topology{} = topology}), do: {:ok, topology}
  defp normalize_topology_update(%Topology{} = topology), do: {:ok, topology}
  defp normalize_topology_update({:error, _reason} = error), do: error

  defp normalize_topology_update(other) do
    {:error,
     Jido.Error.validation_error(
       "Topology update function must return a Jido.Pod.Topology or {:ok, topology}.",
       details: %{result: other}
     )}
  end

  defp persist_topology(%Agent{} = agent, state_key, pod_state, %Topology{} = topology)
       when is_atom(state_key) and is_map(pod_state) do
    updated_state =
      pod_state
      |> Map.put(:topology, topology)
      |> Map.put(:topology_version, topology.version)

    %{agent | state: Map.put(agent.state, state_key, updated_state)}
  end

  defp topology_changed?(%Topology{} = left, %Topology{} = right) do
    drop_topology_version(left) != drop_topology_version(right)
  end

  defp drop_topology_version(%Topology{} = topology) do
    %{topology | version: 0}
  end
end
