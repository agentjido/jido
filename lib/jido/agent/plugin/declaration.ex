defmodule Jido.Agent.Plugin.Declaration do
  @moduledoc false

  alias Jido.Agent.{Extension, Schema}
  alias Jido.Error

  @type t :: %{provider: module(), config: map()}

  @doc false
  @spec normalize(term()) :: {:ok, [t()]} | {:error, Error.t()}
  def normalize(value) do
    with {:ok, declarations} <- Schema.list(value, &declaration/1),
         :ok <- Schema.unique(declarations, & &1.provider),
         :ok <- Schema.unique(declarations, & &1.provider.id()) do
      {:ok, declarations}
    end
  end

  defp declaration(provider) when is_atom(provider), do: declaration({provider, %{}})

  defp declaration({provider, config}) do
    with {:ok, provider} <- Extension.provider(provider),
         :ok <- Schema.plain_map(config),
         :ok <- atom_keys(config),
         :ok <- Schema.static(config) do
      {:ok, %{provider: provider, config: config}}
    end
  end

  defp declaration(value) do
    Error.validation_result(
      :invalid_plugin_declaration,
      [],
      "Expected a Plugin module or {Plugin module, config Map}",
      %{declaration: value}
    )
  end

  defp atom_keys(config) do
    case Enum.find(Map.keys(config), &(not is_atom(&1))) do
      nil ->
        :ok

      key ->
        Error.validation_result(
          :invalid_plugin_config,
          [],
          "Plugin configuration requires atom keys",
          %{key: key}
        )
    end
  end
end
