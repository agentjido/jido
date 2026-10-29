defmodule Jido.Agent.Plugin do
  @moduledoc """
  Executes the Agent callbacks of `Jido.Plugin`.

  Before route selection, an Agent Plugin can inspect the complete Agent state,
  reject a Signal, or prepare one portable package-owned input for execution.
  It cannot change the Signal, caller context, route, or Agent state.

  An Agent Plugin can also own one field in the complete Agent state map and
  one or more Directive types. After executable success, it can inspect the
  current candidate state and validated Directives. It can reduce only its
  owned field.
  """

  alias Jido.Agent
  alias Jido.Agent.{Data, Error, Route}
  alias Jido.Agent.Plugin.{Preparation, RouteSelection, Spec}
  alias Jido.Plugin.Error, as: PluginError
  alias Jido.Plugin.Input
  alias Jido.Plugin.Normalizer
  alias Jido.Signal

  @type state_spec :: :none | {atom(), Zoi.schema()}

  @doc false
  @spec compose_schema(Zoi.schema(), [Jido.Plugin.declaration()] | [Jido.Plugin.Spec.t()]) ::
          {:ok, Zoi.schema()} | {:error, term()}
  def compose_schema(%Zoi.Types.Map{} = domain_schema, declarations) do
    with {:ok, specs} <- Normalizer.normalize_all(declarations),
         do: compose_schema_from_specs(domain_schema, specs)
  end

  def compose_schema(schema, _declarations), do: compose_schema_from_specs(schema, [])

  # Callers pass the specifications from the current validation result.
  @doc false
  def compose_schema_from_specs(%Zoi.Types.Map{fields: fields} = domain_schema, plugin_specs) do
    agent_specs = specs(plugin_specs)

    with :ok <- state_key_conflicts(fields, agent_specs) do
      plugin_fields =
        for %Spec{state_key: key, state_schema: schema} <- agent_specs,
            not is_nil(key),
            into: %{},
            do: {key, schema}

      extended = Zoi.extend(domain_schema, plugin_fields)
      {:ok, %{domain_schema | fields: extended.fields}}
    end
  end

  def compose_schema_from_specs(schema, _specs) do
    PluginError.validation("Agent domain schema must be a field-based Zoi object", %{
      schema: schema
    })
  end

  @doc false
  @spec specs([Jido.Plugin.Spec.t()]) :: [Spec.t()]
  def specs(plugin_specs) do
    Enum.flat_map(plugin_specs, fn
      %{agent: %Spec{} = spec} -> [spec]
      %Spec{} = spec -> [spec]
      _spec -> []
    end)
  end

  @doc false
  @spec prepare(Agent.instance(), Signal.t(), [Jido.Plugin.Spec.t()] | [Spec.t()]) ::
          {:ok, %{optional(module()) => Input.t()}} | {:error, term()}
  def prepare(%Agent{} = agent, %Signal{} = signal, plugin_specs) do
    with {:ok, candidates} <- Route.matching(agent, signal.type) do
      plugin_specs
      |> specs()
      |> Enum.reduce_while({:ok, %{}}, fn spec, {:ok, inputs} ->
        case prepare_one(agent, signal, candidates, spec) do
          :none ->
            {:cont, {:ok, inputs}}

          {:ok, input} ->
            package_input = %Input{} |> Input.put_prepared(input)
            {:cont, {:ok, Map.put(inputs, spec.package, package_input)}}

          {:error, _reason} = error ->
            {:halt, error}
        end
      end)
    end
  end

  @doc false
  @spec select_route(
          Agent.instance(),
          Signal.t(),
          %{optional(module()) => Input.t()},
          [Jido.Plugin.Spec.t()] | [Spec.t()]
        ) :: {:ok, map()} | {:error, term()}
  def select_route(%Agent{} = agent, %Signal{} = signal, inputs, plugin_specs) do
    selectors = Enum.filter(specs(plugin_specs), & &1.route_selector?)

    case selectors do
      [] ->
        Route.select(agent, signal.type)

      [%Spec{} = selector] ->
        select_with_plugin(agent, signal, inputs, selector)

      selectors ->
        PluginError.validation("Only one Agent Plugin can select routes", %{
          plugins: Enum.map(selectors, & &1.package)
        })
    end
  end

  @doc false
  @spec validate_route_contract([map()], [map()]) :: :ok | {:error, term()}
  def validate_route_contract(routes, plugins) do
    case route_selector_modules(plugins) do
      [] ->
        validate_routes_without_selector(routes)

      [_selector] ->
        validate_duplicate_route_aliases(routes)

      selectors ->
        PluginError.validation("Only one Agent Plugin can select routes", %{
          plugins: selectors
        })
    end
  end

  @doc false
  @spec directive_owner([Spec.t()], struct()) :: Spec.t() | nil
  def directive_owner(specs, %{__struct__: directive_module}) do
    Enum.find(specs, &(directive_module in &1.directive_modules))
  end

  def directive_owner(_specs, _directive), do: nil

  defp prepare_one(agent, signal, candidates, %Spec{} = spec) do
    if function_exported?(spec.module, :prepare, 2) do
      preparation = %Preparation{
        plugin: spec.package,
        agent_id: agent.id,
        agent_module: agent.module,
        agent_state: agent.state,
        signal: signal,
        plugin_state: plugin_state(agent.state, spec.state_key),
        route_candidates: candidates
      }

      PluginError.safe_apply(
        spec.package,
        spec.module,
        :prepare,
        [preparation, spec.options],
        "Agent Plugin preparation failed"
      )
      |> validate_preparation_result(spec)
    else
      :none
    end
  end

  defp validate_preparation_result({:ok, input}, spec) do
    case Jido.PortableTerm.validate(input, [:plugin_inputs, spec.package, :prepared]) do
      :ok ->
        {:ok, input}

      {:error, path} ->
        PluginError.invalid_callback(
          "Agent Plugin prepare/2 returned a non-portable input",
          spec.package,
          spec.module,
          %{code: :non_portable_term, path: path}
        )
    end
  end

  defp validate_preparation_result({:error, _reason} = error, _spec), do: error

  defp validate_preparation_result(result, spec) do
    PluginError.invalid_callback(
      "Agent Plugin prepare/2 returned an invalid result",
      spec.package,
      spec.module,
      %{result: result}
    )
  end

  defp plugin_state(_state, nil), do: nil
  defp plugin_state(state, key), do: Map.get(state, key)

  defp select_with_plugin(agent, signal, inputs, %Spec{} = spec) do
    with {:ok, candidates} <- Route.matching(agent, signal.type),
         {:ok, candidates} <- require_candidates(candidates, signal.type),
         :ok <- validate_candidate_aliases(candidates) do
      package_input = Map.get(inputs, spec.package, %Input{})

      selection = %RouteSelection{
        plugin: spec.package,
        agent_id: agent.id,
        agent_module: agent.module,
        agent_state: agent.state,
        plugin_state: plugin_state(agent.state, spec.state_key),
        signal: signal,
        prepared_input: package_input.prepared,
        candidates: candidates
      }

      spec.package
      |> PluginError.safe_apply(
        spec.module,
        :select_route,
        [selection, spec.options],
        "Agent Plugin route selection failed"
      )
      |> validate_route_selection(spec, candidates)
    end
  end

  defp require_candidates([], type),
    do:
      Jido.Agent.Error.fail(
        :unmatched_input,
        [:routes],
        "No route accepts this Signal type",
        %{type: type}
      )

  defp require_candidates(candidates, _type), do: {:ok, candidates}

  defp validate_candidate_aliases([_candidate]), do: :ok

  defp validate_candidate_aliases(candidates) do
    aliases = Enum.map(candidates, & &1.as)

    if Enum.all?(aliases, &(is_atom(&1) and &1 not in [nil, true, false])) and
         Enum.uniq(aliases) == aliases do
      :ok
    else
      {:error,
       PluginError.execution(
         "Ambiguous matching routes require unique aliases",
         :core,
         __MODULE__,
         %{code: :ambiguous_route_aliases, aliases: aliases}
       )}
    end
  end

  defp validate_route_selection(:default, _spec, [candidate]), do: {:ok, candidate}

  defp validate_route_selection(:default, spec, candidates) do
    {:error,
     PluginError.execution(
       "Agent Plugin left an ambiguous route selection unresolved",
       spec.package,
       spec.module,
       %{
         code: :ambiguous_route_selection,
         aliases: Enum.map(candidates, & &1.as)
       }
     )}
  end

  defp validate_route_selection({:ok, route_as}, spec, candidates)
       when is_atom(route_as) and route_as not in [nil, true, false] do
    case Enum.find(candidates, &(&1.as == route_as)) do
      nil ->
        {:error,
         PluginError.execution(
           "Agent Plugin selected a route that does not match the Signal",
           spec.package,
           spec.module,
           %{
             code: :invalid_route_selection,
             route: route_as,
             candidates: Enum.map(candidates, & &1.as)
           }
         )}

      route ->
        {:ok, route}
    end
  end

  defp validate_route_selection({:error, _reason} = error, _spec, _candidates), do: error

  defp validate_route_selection(result, spec, _candidates) do
    PluginError.invalid_callback(
      "Agent Plugin select_route/2 returned an invalid result",
      spec.package,
      spec.module,
      %{result: result}
    )
  end

  defp route_selector_modules(plugins) do
    for %{provider: module} <- plugins,
        Code.ensure_loaded?(module) and function_exported?(module, :select_route, 2),
        do: module
  end

  defp validate_duplicate_route_aliases(routes) do
    routes
    |> Enum.group_by(& &1.path)
    |> Enum.reduce_while(:ok, fn
      {_path, [_route]}, :ok ->
        {:cont, :ok}

      {path, duplicates}, :ok ->
        aliases = Enum.map(duplicates, & &1.as)

        if Enum.all?(aliases, &(is_atom(&1) and &1 not in [nil, true, false])) do
          {:cont, :ok}
        else
          {:halt,
           PluginError.validation("Duplicate routes require aliases for Plugin selection", %{
             path: path,
             aliases: aliases
           })}
        end
    end)
  end

  defp validate_routes_without_selector(routes) do
    with :ok <- Data.unique(routes, & &1.path) do
      case Enum.find(routes, &(not is_nil(&1.as) and Data.wildcard?(&1.path))) do
        nil ->
          :ok

        route ->
          Error.fail(
            :wildcard_helper,
            [:as],
            "A helper requires an exact input type",
            %{path: route.path, as: route.as}
          )
      end
    end
  end

  defp state_key_conflicts(fields, specs) do
    domain_keys = MapSet.new(Keyword.keys(fields))

    case Enum.find(specs, &MapSet.member?(domain_keys, &1.state_key)) do
      nil ->
        :ok

      spec ->
        PluginError.validation("Plugin-owned Agent state key conflicts with the domain schema", %{
          plugin: spec.package,
          state_key: spec.state_key
        })
    end
  end
end
