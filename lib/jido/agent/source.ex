defmodule Jido.Agent.Source do
  @moduledoc false

  alias Jido.Agent.{Authoring, Validation}

  def definition(source) do
    with {:ok, definition, _specs, _schema} <- definition_with_plugins(source),
         do: {:ok, definition}
  end

  def definition_with_plugins(%Jido.Agent{} = definition),
    do: Validation.validate_definition_with_plugins(definition)

  def definition_with_plugins(module) do
    case config(module) do
      {:ok, config} -> Validation.dependencies(config)
      :custom -> Authoring.error("Expected an Agent module", %{module: module})
      {:error, _} = error -> error
    end
  end

  def instantiate_with_plugins(module, overrides, fallback \\ nil) do
    case config(module) do
      {:ok, config} ->
        Validation.instantiate_validated(Validation.dependencies(config), overrides)

      :custom when is_function(fallback, 2) ->
        fallback.(module, overrides)

      :custom ->
        Authoring.error("Expected an Agent module", %{module: module})

      {:error, _} = error ->
        error
    end
  end

  defp config(module) when is_atom(module) and not is_nil(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        if function_exported?(module, :__agent_config__, 0),
          do: read_config(module),
          else: :custom

      {:error, reason} ->
        Authoring.error("Agent module could not be loaded", %{module: module, reason: reason})
    end
  end

  defp config(_source), do: Authoring.error("Expected an Agent module")

  defp read_config(module) do
    case module.__agent_config__() do
      %Jido.Agent{id: nil, state: nil, module: ^module} = definition -> {:ok, definition}
      attrs -> Validation.module_definition(module, attrs)
    end
  rescue
    error -> config_error(module, :error, error)
  catch
    kind, reason -> config_error(module, kind, reason)
  end

  defp config_error(module, kind, reason),
    do:
      Authoring.error("Agent module configuration failed", %{
        module: module,
        kind: kind,
        reason: reason
      })
end
