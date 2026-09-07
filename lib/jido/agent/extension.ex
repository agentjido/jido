defmodule Jido.Agent.Extension do
  @moduledoc """
  Lowers additional Agent DSL declarations into ordinary Agent configuration.

  Pass Spark extension modules through `use Jido.Agent, extensions: [Extension]`.
  Each extension also implements `lower_agent/2`. Core first collects its own
  schema, routes and Plugins. It then calls extensions in declaration order with
  that configuration and the remaining foreign entities from `agent do`.

  Return updated configuration and any entities owned by another extension.
  All entities must be consumed. Common Agent validation still applies, and
  execution uses the same runtime as Builder and direct definitions.

  Lowering must be static: do not start processes, run Actions or contact external
  services. Keep semantic lowering usable from data-based authoring. Extensions
  do not create another Agent runtime or bypass state validation.
  """

  @callback lower_agent(map(), [struct()]) ::
              {:ok, map(), [struct()]} | {:error, Exception.t()}

  @doc false
  def lower(extensions, config, entities) when is_list(extensions) do
    if length(extensions) != length(Enum.uniq(extensions)) do
      error("Duplicate Agent extension")
    else
      Enum.reduce_while(extensions, {:ok, config, entities}, fn extension, {:ok, attrs, rest} ->
        if is_atom(extension) and Code.ensure_loaded?(extension) and
             function_exported?(extension, :lower_agent, 2) do
          case extension.lower_agent(attrs, rest) do
            {:ok, result, remaining}
            when is_map(result) and not is_struct(result) and is_list(remaining) ->
              {:cont, {:ok, result, remaining}}

            {:error, error} when is_exception(error) ->
              {:halt, {:error, error}}

            other ->
              {:halt,
               error("Invalid Agent extension result", %{extension: extension, result: other})}
          end
        else
          {:halt, error("Agent extension must implement lower_agent/2", %{extension: extension})}
        end
      end)
      |> finish()
    end
  end

  def lower(_extensions, _config, _entities), do: error("Agent extensions must be a list")

  defp finish({:ok, config, []}), do: {:ok, config}

  defp finish({:ok, _config, entities}),
    do: error("Unclaimed Agent extension entities", %{entities: entities})

  defp finish({:error, _} = error), do: error

  defp error(message, details \\ %{}), do: Jido.Agent.Authoring.error(message, details)
end
