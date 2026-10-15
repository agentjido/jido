defmodule Jido.Agent.Extension do
  @moduledoc """
  Lowers additional Agent DSL declarations into ordinary Agent configuration.

  Pass Spark extension modules through `use Jido.Agent, extensions: [Extension]`.
  Each extension also implements `lower_agent/2`. Core first collects its own
  schema, routes and Plugins. It then calls extensions in declaration order with
  that configuration and the remaining foreign entities from `agent do`.

  Return updated configuration and any entities owned by another extension.
  All entities must be consumed. Common Agent validation still applies, and
  execution uses the same runtime as direct definitions.

  Lowering must be static: do not start processes, run Actions or contact external
  services. Keep semantic lowering usable from data-based authoring. Extensions
  do not create another Agent runtime or bypass state validation.

  An extension can implement `route_target_options/0` to own keyword route
  targets. Core assigns each target to its owner before it calls `lower_agent/2`.
  """

  alias Jido.Agent.Authoring

  @callback lower_agent(map(), [struct()]) ::
              {:ok, map(), [struct()]} | {:error, Exception.t()}

  @doc "Returns the keyword route target options that this extension owns."
  @callback route_target_options() :: [atom()]

  @optional_callbacks route_target_options: 0

  @doc false
  @spec route_target_extension([module()], atom()) :: {:ok, module()} | {:error, term()}
  def route_target_extension(extensions, option) when is_list(extensions) and is_atom(option) do
    with {:ok, claims} <- route_target_claims(extensions), do: route_target_claim(claims, option)
  end

  def route_target_extension(_extensions, option), do: invalid_route_option(option)

  defp route_target_claims(extensions) do
    Enum.reduce_while(extensions, {:ok, %{}}, fn extension, {:ok, claims} ->
      if is_atom(extension) and Code.ensure_loaded?(extension) and
           function_exported?(extension, :route_target_options, 0) do
        options = extension.route_target_options()

        if is_list(options) and options == Enum.uniq(options) and Enum.all?(options, &is_atom/1) do
          claims =
            Enum.reduce(
              options,
              claims,
              &Map.update(&2, &1, [extension], fn owners -> [extension | owners] end)
            )

          {:cont, {:ok, claims}}
        else
          {:halt,
           Authoring.error(
             "Agent extension route_target_options/0 must return unique atom names",
             %{
               extension: extension,
               options: options
             }
           )}
        end
      else
        {:cont, {:ok, claims}}
      end
    end)
  end

  @doc """
  Lowers static extension data to ordinary Agent authoring data.

  The function calls each extension in declaration order. It returns only the
  lowered core configuration after every entity and route target is claimed.
  Pass the returned map to `Jido.Agent.new/1` or
  another static authoring boundary. This function starts no process and runs
  no Action or Flow.
  """
  @spec lower([module()], map(), [struct()]) ::
          {:ok, map()} | {:error, Exception.t()}
  def lower(extensions, config, entities),
    do:
      Jido.Agent.Authoring.Extension.lower(
        extensions,
        config,
        entities,
        :agent,
        &claim_route_targets/2
      )

  defp claim_route_targets(extensions, %{routes: routes} = config) when is_list(routes) do
    case Enum.find_value(routes, &route_target/1) do
      nil ->
        {:ok, config}

      %{option: option} when is_atom(option) ->
        with {:ok, claims} <- route_target_claims(extensions),
             {:ok, routes} <- claim_routes(claims, routes) do
          {:ok, %{config | routes: routes}}
        end

      %{option: option} ->
        invalid_route_option(option)
    end
  end

  defp claim_route_targets(_extensions, config), do: {:ok, config}

  defp route_target(%{target: {%Jido.Agent.Extension.RouteTarget{} = target, _defaults}}),
    do: target

  defp route_target(%{target: %Jido.Agent.Extension.RouteTarget{} = target}), do: target
  defp route_target(_route), do: nil

  defp claim_routes(claims, routes) do
    Enum.reduce_while(routes, {:ok, []}, fn route, {:ok, claimed} ->
      case claim_route_target(claims, route) do
        {:ok, route} -> {:cont, {:ok, [route | claimed]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, routes} -> {:ok, Enum.reverse(routes)}
      error -> error
    end
  end

  defp claim_route_target(
         claims,
         %{target: {%Jido.Agent.Extension.RouteTarget{} = target, defaults}} = route
       ) do
    with {:ok, target} <- claim_route_target_value(claims, target),
         do: {:ok, %{route | target: {target, defaults}}}
  end

  defp claim_route_target(
         claims,
         %{target: %Jido.Agent.Extension.RouteTarget{} = target} = route
       ) do
    with {:ok, target} <- claim_route_target_value(claims, target),
         do: {:ok, %{route | target: target}}
  end

  defp claim_route_target(_claims, route), do: {:ok, route}

  defp claim_route_target_value(claims, target) do
    with {:ok, extension} <- route_target_claim(claims, target.option),
         do: {:ok, %{target | extension: extension}}
  end

  defp route_target_claim(claims, option) when is_atom(option) do
    case Map.get(claims, option, []) do
      [extension] ->
        {:ok, extension}

      [] ->
        Authoring.error("Unknown Agent extension route target option #{inspect(option)}", %{
          option: option
        })

      extensions ->
        Authoring.error("Conflicting Agent extension route target option #{inspect(option)}", %{
          option: option,
          extensions: Enum.reverse(extensions)
        })
    end
  end

  defp route_target_claim(_claims, option), do: invalid_route_option(option)

  defp invalid_route_option(option),
    do: Authoring.error("Invalid Agent extension route target option", %{option: option})
end
