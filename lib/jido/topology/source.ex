defmodule Jido.Topology.Source do
  @moduledoc false
  alias Jido.Agent.Authoring

  # Includes accept static configs. Runtime children also accept legacy modules
  # and can infer a director from an explicit Agent block.
  def load(source, ancestors, mode) when is_atom(source) and not is_nil(source) do
    cond do
      source in ancestors ->
        message =
          if mode == :include, do: "Recursive topology inclusion", else: "Child topology cycle"

        Authoring.error(message, %{module: source})

      not Code.ensure_loaded?(source) ->
        invalid(mode)

      function_exported?(source, :__topology_config__, 0) ->
        config = source.__topology_config__()

        owner =
          if mode == :child and function_exported?(source, :__topology_owner__?, 0) and
               source.__topology_owner__?(),
             do: source.owner()

        {:ok, config, owner, [source | ancestors]}

      mode == :child and function_exported?(source, :topology, 0) ->
        {:ok, source.topology(), nil, [source | ancestors]}

      true ->
        invalid(mode)
    end
  rescue
    error -> source_error(source, :error, error)
  catch
    kind, reason -> source_error(source, kind, reason)
  end

  def load(value, ancestors, _mode) when is_map(value) or is_list(value),
    do: {:ok, value, nil, ancestors}

  def load(_, _, _), do: Authoring.error("Expected a topology module or definition")

  defp invalid(:child), do: Authoring.error("Expected a topology module")
  defp invalid(:include), do: Authoring.error("Expected a topology module or definition")

  defp source_error(module, kind, reason),
    do:
      Authoring.error("Topology module configuration failed", %{
        module: module,
        kind: kind,
        reason: reason
      })
end
