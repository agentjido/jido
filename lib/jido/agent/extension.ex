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

  An extension can implement `route_target_options/0` to own keyword route
  targets. Core assigns each target to its owner before it calls `lower_agent/2`.
  """

  @callback lower_agent(map(), [struct()]) ::
              {:ok, map(), [struct()]} | {:error, Exception.t()}

  @doc "Returns the keyword route target options that this extension owns."
  @callback route_target_options() :: [atom()]

  @optional_callbacks route_target_options: 0

  @doc false
  def route_target_extension(extensions, option) when is_list(extensions) and is_atom(option) do
    Enum.reduce_while(extensions, {:ok, []}, fn extension, {:ok, claims} ->
      if is_atom(extension) and Code.ensure_loaded?(extension) and
           function_exported?(extension, :route_target_options, 0) do
        options = extension.route_target_options()

        if is_list(options) and options == Enum.uniq(options) and Enum.all?(options, &is_atom/1) do
          claims = if option in options, do: [extension | claims], else: claims
          {:cont, {:ok, claims}}
        else
          {:halt,
           error("Agent extension route_target_options/0 must return unique atom names", %{
             extension: extension,
             options: options
           })}
        end
      else
        {:cont, {:ok, claims}}
      end
    end)
    |> route_target_claim(option)
  end

  def route_target_extension(_extensions, option),
    do: error("Invalid Agent extension route target option", %{option: option})

  @doc false
  def lower(extensions, config, entities) when is_list(extensions) do
    if length(extensions) != length(Enum.uniq(extensions)) do
      error("Duplicate Agent extension")
    else
      with {:ok, config} <- claim_route_targets(extensions, config) do
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
            {:halt,
             error("Agent extension must implement lower_agent/2", %{extension: extension})}
          end
        end)
        |> finish()
      end
    end
  end

  def lower(_extensions, _config, _entities), do: error("Agent extensions must be a list")

  defp finish({:ok, config, []}), do: {:ok, config}

  defp finish({:ok, _config, entities}),
    do: error("Unclaimed Agent extension entities", %{entities: entities})

  defp finish({:error, _} = error), do: error

  defp claim_route_targets(extensions, %{routes: routes} = config) when is_list(routes) do
    Enum.reduce_while(routes, {:ok, []}, fn route, {:ok, claimed} ->
      case claim_route_target(extensions, route) do
        {:ok, route} -> {:cont, {:ok, [route | claimed]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, routes} -> {:ok, %{config | routes: Enum.reverse(routes)}}
      error -> error
    end
  end

  defp claim_route_targets(_extensions, config), do: {:ok, config}

  defp claim_route_target(
         extensions,
         %{target: {%Jido.Agent.Extension.RouteTarget{} = target, defaults}} = route
       ) do
    with {:ok, target} <- claim_route_target_value(extensions, target),
         do: {:ok, %{route | target: {target, defaults}}}
  end

  defp claim_route_target(
         extensions,
         %{target: %Jido.Agent.Extension.RouteTarget{} = target} = route
       ) do
    with {:ok, target} <- claim_route_target_value(extensions, target),
         do: {:ok, %{route | target: target}}
  end

  defp claim_route_target(_extensions, route), do: {:ok, route}

  defp claim_route_target_value(extensions, target) do
    with {:ok, extension} <- route_target_extension(extensions, target.option),
         do: {:ok, %{target | extension: extension}}
  end

  defp route_target_claim({:ok, [extension]}, _option), do: {:ok, extension}

  defp route_target_claim({:ok, []}, option),
    do: error("Unknown Agent extension route target option #{inspect(option)}", %{option: option})

  defp route_target_claim({:ok, extensions}, option),
    do:
      error("Conflicting Agent extension route target option #{inspect(option)}", %{
        option: option,
        extensions: Enum.reverse(extensions)
      })

  defp route_target_claim({:error, _} = error, _option), do: error

  defp error(message, details \\ %{}), do: Jido.Agent.Authoring.error(message, details)
end
