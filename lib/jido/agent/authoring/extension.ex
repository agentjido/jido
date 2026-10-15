defmodule Jido.Agent.Authoring.Extension do
  @moduledoc false

  alias Jido.Agent.Authoring

  def lower(extensions, config, entities, kind, prepare \\ &unchanged/2) do
    label = if kind == :agent, do: "Agent", else: "Topology"
    callback = if kind == :agent, do: :lower_agent, else: :lower_topology

    with :ok <- validate(extensions, config, entities, label),
         {:ok, config} <- prepare.(extensions, config) do
      Enum.reduce_while(extensions, {:ok, config, entities}, fn extension, {:ok, attrs, rest} ->
        if is_atom(extension) and Code.ensure_loaded?(extension) and
             function_exported?(extension, callback, 2) do
          case apply(extension, callback, [attrs, rest]) do
            {:ok, result, remaining} when is_map(result) and not is_struct(result) ->
              if proper_list?(remaining),
                do: {:cont, {:ok, result, remaining}},
                else: {:halt, invalid_result(label, extension, {:ok, result, remaining})}

            {:error, error} when is_exception(error) ->
              {:halt, {:error, error}}

            other ->
              {:halt, invalid_result(label, extension, other)}
          end
        else
          {:halt,
           Authoring.error("#{label} extension must implement #{callback}/2", %{
             extension: extension
           })}
        end
      end)
      |> finish(label)
    end
  end

  defp unchanged(_extensions, config), do: {:ok, config}

  defp validate(extensions, config, entities, label) do
    cond do
      not proper_list?(extensions) or not proper_list?(entities) ->
        Authoring.error("#{label} extensions and entities must be proper lists")

      not is_map(config) or is_struct(config) ->
        Authoring.error("#{label} extensions require a list, plain config map, and entity list")

      length(extensions) != length(Enum.uniq(extensions)) ->
        Authoring.error("Duplicate #{label} extension")

      true ->
        :ok
    end
  end

  defp proper_list?([]), do: true
  defp proper_list?([_head | tail]), do: proper_list?(tail)
  defp proper_list?(_tail), do: false

  defp invalid_result(label, extension, result),
    do:
      Authoring.error("Invalid #{label} extension result", %{extension: extension, result: result})

  defp finish({:ok, config, []}, _label), do: {:ok, config}

  defp finish({:ok, _config, entities}, label),
    do: Authoring.error("Unclaimed #{label} extension entities", %{entities: entities})

  defp finish({:error, _} = error, _label), do: error
end
