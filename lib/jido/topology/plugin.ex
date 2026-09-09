defmodule Jido.Topology.Plugin do
  @moduledoc """
  Pure Topology-owned facet of a `Jido.Plugin` package.

  A callback can return current canonical Bus resources, ownership
  relationships, and Bus subscriptions. It cannot start a process, activate a
  plan, persist data, or add a new resource kind through this contract.
  """

  alias Jido.Plugin.Error, as: PluginError
  alias Jido.Topology.Plugin.{Context, Contribution, Spec}
  alias Jido.Topology.Validation

  @doc "Defines a Topology-owned Plugin facet."
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Jido.Topology.Plugin

      @doc false
      def __jido_plugin_facet__, do: :topology
    end
  end

  @callback contribute(context :: Context.t(), opts :: keyword()) ::
              {:ok, Contribution.t()} | {:error, term()}

  @doc false
  @spec contribute(Jido.Plugin.Spec.t(), Context.t()) ::
          {:ok, Contribution.t()} | {:error, term()}
  def contribute(%{topology: %Spec{} = spec}, %Context{} = context) do
    with {:ok, context} <- Context.validate(context),
         :ok <- validate_context(context, spec),
         result <-
           PluginError.safe_apply(
             spec.package,
             spec.module,
             :contribute,
             [context, spec.options],
             "Topology Plugin contribution failed"
           ),
         {:ok, contribution} <- callback_contribution(result, spec),
         :ok <- contribution_owner(contribution, spec),
         {:ok, resources} <- validate_entries(:bus, contribution.resources),
         {:ok, relationships} <- validate_entries(:owns, contribution.relationships),
         {:ok, connections} <- validate_entries(:subscribe, contribution.connections) do
      {:ok,
       %{
         contribution
         | resources: resources,
           relationships: relationships,
           connections: connections
       }}
    end
  end

  @doc false
  @spec context(Jido.Plugin.Spec.t(), String.t(), module()) :: Context.t()
  def context(%{topology: %Spec{} = spec}, agent_key, agent_module)
      when is_binary(agent_key) and is_atom(agent_module) do
    %Context{
      plugin: spec.package,
      plugin_vsn: spec.vsn,
      agent_key: agent_key,
      agent_module: agent_module
    }
  end

  defp callback_contribution({:ok, %Contribution{} = contribution}, spec) do
    case Contribution.validate(contribution) do
      {:ok, contribution} ->
        {:ok, contribution}

      {:error, reason} ->
        PluginError.invalid_callback(
          "Topology Plugin returned an invalid contribution",
          spec.package,
          spec.module,
          %{reason: reason}
        )
    end
  end

  defp callback_contribution({:error, _reason} = error, _spec), do: error

  defp callback_contribution(result, spec) do
    PluginError.invalid_callback(
      "Topology Plugin contribute/2 returned an invalid result",
      spec.package,
      spec.module,
      %{result: result}
    )
  end

  defp contribution_owner(%Contribution{plugin: package}, %Spec{package: package}), do: :ok

  defp contribution_owner(contribution, spec) do
    PluginError.invalid_callback(
      "Topology Plugin contribution changed package identity",
      spec.package,
      spec.module,
      %{actual: contribution.plugin}
    )
  end

  defp validate_entries(kind, entries) do
    Jido.Agent.Authoring.traverse(entries, &Validation.entry(kind, &1))
  end

  defp validate_context(
         %Context{plugin: package, plugin_vsn: vsn},
         %Spec{package: package, vsn: vsn}
       ),
       do: :ok

  defp validate_context(context, spec) do
    PluginError.validation("Topology Plugin context does not match its owner", %{
      plugin: spec.package,
      facet: spec.module,
      context: context
    })
  end
end
