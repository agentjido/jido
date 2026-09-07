defmodule Jido.Topology.Extension do
  @moduledoc """
  Lowers additional Topology DSL declarations into ordinary Topology configuration.

  Pass Spark extension modules through
  `use Jido.Topology, extensions: [Extension]`. Each extension also implements
  `lower_topology/2`. Core first collects its Agents, groups, Buses,
  relationships, connections, composition data, and startup policy. It then
  calls extensions in declaration order with that configuration and the
  remaining foreign entities from all extension sections.

  Return updated configuration and any entities owned by another extension.
  Consume only entity structs that the extension owns, and keep the relative
  order of all remaining entities. Do not depend on order between different
  Spark sections. All entities must be consumed. Common Topology validation
  still applies, and activation uses the same controller as Builder and direct
  definitions.

  The callback receives entity structs, not the raw Spark DSL state. Put each
  input that lowering needs in an entity. Use a distinct entity struct when
  two extension sections have different meanings.

  Lowering must be static: do not start processes, run Actions, or contact
  external services. An extension adds authoring syntax. It does not add a
  second Topology runtime or bypass normal definition and composition checks.
  """

  @type config :: map()
  @type entities :: [struct()]
  @type lower_result :: {:ok, config(), entities()} | {:error, Exception.t()}

  @callback lower_topology(config(), entities()) :: lower_result()

  @doc false
  @spec lower([module()], config(), entities()) ::
          {:ok, config()} | {:error, Exception.t()}
  def lower(extensions, config, entities) when is_list(extensions) do
    if length(extensions) != length(Enum.uniq(extensions)) do
      error("Duplicate Topology extension")
    else
      Enum.reduce_while(extensions, {:ok, config, entities}, fn extension, {:ok, attrs, rest} ->
        if is_atom(extension) and Code.ensure_loaded?(extension) and
             function_exported?(extension, :lower_topology, 2) do
          case extension.lower_topology(attrs, rest) do
            {:ok, result, remaining}
            when is_map(result) and not is_struct(result) and is_list(remaining) ->
              {:cont, {:ok, result, remaining}}

            {:error, error} when is_exception(error) ->
              {:halt, {:error, error}}

            other ->
              {:halt,
               error("Invalid Topology extension result", %{
                 extension: extension,
                 result: other
               })}
          end
        else
          {:halt,
           error("Topology extension must implement lower_topology/2", %{
             extension: extension
           })}
        end
      end)
      |> finish()
    end
  end

  def lower(_extensions, _config, _entities),
    do: error("Topology extensions must be a list")

  defp finish({:ok, config, []}), do: {:ok, config}

  defp finish({:ok, _config, entities}),
    do: error("Unclaimed Topology extension entities", %{entities: entities})

  defp finish({:error, _} = error), do: error

  defp error(message, details \\ %{}), do: Jido.Agent.Authoring.error(message, details)
end
