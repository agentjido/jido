defmodule Jido.Pod.Plugin do
  @moduledoc """
  Default singleton plugin for pod-wrapped agents.

  The plugin reserves the `:__pod__` state slice and persists the resolved
  topology snapshot as ordinary agent state, which lets the existing
  `Persist` and `Storage` adapters continue to work unchanged.
  """

  alias Jido.Pod.Topology

  @state_key :__pod__
  @capability :pod

  use Jido.Plugin,
    name: "pod",
    state_key: @state_key,
    actions: [],
    schema:
      Zoi.object(%{
        topology: Zoi.any(description: "Resolved pod topology.") |> Zoi.optional(),
        topology_version:
          Zoi.integer(description: "Resolved topology version.") |> Zoi.default(1),
        metadata:
          Zoi.map(description: "Pod-level runtime metadata owned by the plugin.")
          |> Zoi.default(%{})
      }),
    capabilities: [@capability],
    singleton: true

  @doc false
  @spec state_key_atom() :: atom()
  def state_key_atom, do: @state_key

  @doc false
  @spec capability() :: atom()
  def capability, do: @capability

  @doc """
  Builds the canonical default state for a pod plugin.
  """
  @spec build_state(module() | Topology.t(), map()) :: {:ok, map()} | {:error, term()}
  def build_state(%Topology{} = topology, overrides) when is_map(overrides) do
    {:ok,
     %{
       topology: topology,
       topology_version: topology.version,
       metadata: %{}
     }
     |> deep_merge(overrides)}
  end

  def build_state(agent_module, overrides) when is_atom(agent_module) and is_map(overrides) do
    cond do
      function_exported?(agent_module, :topology, 0) ->
        build_state(agent_module.topology(), overrides)

      true ->
        {:error,
         Jido.Error.validation_error(
           "#{inspect(agent_module)} does not export topology/0 required by pod plugins."
         )}
    end
  end

  @impl true
  def mount(%{agent_module: agent_module}, config) when is_map(config) do
    topology = Map.get(config, :topology, agent_module)
    metadata = Map.get(config, :metadata, %{})
    build_state(topology, %{metadata: metadata})
  end

  def mount(agent, _config) do
    {:error,
     Jido.Error.validation_error(
       "Pod plugin mount expected an agent struct with agent_module.",
       details: %{agent: agent}
     )}
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end
end
