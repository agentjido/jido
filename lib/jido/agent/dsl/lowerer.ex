defmodule Jido.Agent.DSL.Lowerer do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.DSL.{Plugin, Route, Schedule}
  alias Jido.Agent.Plugin, as: AgentPlugin
  alias Jido.Agent.PluginDefaults
  alias Jido.Agent.Schedule, as: AgentSchedule
  alias Jido.Error
  alias Jido.Signal.Router

  @unset :__jido_agent_dsl_unset__

  @doc "Lowers one Spark module into a canonical Agent definition."
  @spec lower(module(), map()) :: {:ok, Agent.t()} | {:error, Exception.t()}
  def lower(module, opts, env \\ nil) do
    entities = Spark.Dsl.Extension.get_entities(module, [:agent])

    with {:ok, root} <- root_options(module, opts, env),
         {:ok, compatibility_plugins} <- lower_plugins(Map.get(opts, :plugins, [])),
         {:ok, compatibility_routes} <- lower_routes(Map.get(opts, :routes, [])),
         {:ok, compatibility_schedules} <- lower_schedules(Map.get(opts, :schedules, [])),
         {:ok, plugins, routes, schedules} <- lower_entities(entities),
         {:ok, agent} <-
           Agent.new(
             Map.merge(root, %{
               plugins: compatibility_plugins ++ plugins,
               routes: compatibility_routes ++ routes,
               schedules: compatibility_schedules ++ schedules
             })
           ) do
      {:ok, agent}
    end
  end

  @doc false
  @spec source_map(module(), String.t() | nil) :: map()
  def source_map(module, default_file \\ nil) do
    module
    |> Spark.Dsl.Extension.get_entities([:agent])
    |> Enum.reduce({%{}, %{plugins: 0, routes: 0, schedules: 0}}, fn entity, {map, indexes} ->
      {kind, index} = entity_path(entity, indexes)
      location = source_location(entity, default_file)
      path = [kind, index]
      {Map.put(map, path, location), Map.update!(indexes, kind, &(&1 + 1))}
    end)
    |> elem(0)
  end

  defp root_options(module, opts, env) do
    with {:ok, name} <- root_option(module, opts, :name),
         {:ok, description} <- root_option(module, opts, :description),
         {:ok, state_schema} <- state_schema_option(module, opts, env),
         {:ok, plugin_defaults} <- root_option(module, opts, :plugin_defaults),
         {:ok, metadata} <- root_option(module, opts, :metadata) do
      {:ok,
       %{
         name: name,
         description: description,
         state_schema: state_schema || [],
         plugin_defaults: plugin_defaults || %PluginDefaults{},
         extensions: Map.get(opts, :agent_extensions, []),
         metadata: metadata || %{}
       }}
    end
  end

  defp state_schema_option(module, opts, env) do
    with {:ok, value} <- root_option(module, opts, :state_schema) do
      if is_nil(env) or Map.has_key?(opts, :state_schema) or is_nil(value) do
        {:ok, value}
      else
        try do
          {evaluated, _binding} = Code.eval_quoted(value, [], env)
          {:ok, evaluated}
        rescue
          error -> {:error, error}
        end
      end
    end
  end

  defp root_option(module, opts, key) do
    section_value = Spark.Dsl.Extension.get_opt(module, [:agent], key, @unset)

    case {Map.fetch(opts, key), section_value} do
      {{:ok, _use_value}, value} when value != @unset ->
        {:error, error("Agent root option is declared more than once", %{field: key})}

      {{:ok, use_value}, @unset} ->
        {:ok, use_value}

      {:error, @unset} ->
        {:ok, nil}

      {:error, value} ->
        {:ok, value}
    end
  end

  defp lower_entities(entities) do
    entities
    |> Enum.reduce_while({:ok, [], [], []}, fn entity, {:ok, plugins, routes, schedules} ->
      case lower_entity(entity) do
        {:ok, {:plugins, value}} -> {:cont, {:ok, [value | plugins], routes, schedules}}
        {:ok, {:routes, value}} -> {:cont, {:ok, plugins, [value | routes], schedules}}
        {:ok, {:schedules, value}} -> {:cont, {:ok, plugins, routes, [value | schedules]}}
        {:error, validation_error} -> {:halt, {:error, validation_error}}
      end
    end)
    |> then(fn
      {:ok, plugins, routes, schedules} ->
        {:ok, Enum.reverse(plugins), Enum.reverse(routes), Enum.reverse(schedules)}

      {:error, _error} = error ->
        error
    end)
  end

  defp lower_entity(%Plugin{} = plugin) do
    case AgentPlugin.new(
           module: plugin.module,
           as: plugin.as,
           config: plugin.config,
           metadata: plugin.metadata
         ) do
      {:ok, value} -> {:ok, {:plugins, value}}
      {:error, validation_error} -> {:error, validation_error}
    end
  end

  defp lower_entity(%Route{} = route) do
    target = if route.params == %{}, do: route.target, else: {route.target, route.params}

    route_spec =
      if is_nil(route.match),
        do: {route.path, target, route.priority},
        else: {route.path, route.match, target, route.priority}

    case Router.normalize(route_spec) do
      {:ok, [value]} -> {:ok, {:routes, value}}
      {:error, reason} -> {:error, error("invalid Agent route", %{reason: reason})}
    end
  end

  defp lower_entity(%Schedule{} = schedule) do
    case AgentSchedule.new(
           name: schedule.name,
           cron_expression: schedule.cron_expression,
           signal_type: schedule.signal_type,
           timezone: schedule.timezone,
           data: schedule.data,
           metadata: schedule.metadata
         ) do
      {:ok, value} -> {:ok, {:schedules, value}}
      {:error, validation_error} -> {:error, validation_error}
    end
  end

  defp lower_plugins(plugins) when is_list(plugins) do
    map_list(plugins, &legacy_plugin/1)
  end

  defp lower_plugins(_plugins), do: {:error, error("Agent plugins must be a list")}

  defp legacy_plugin(%AgentPlugin{} = plugin), do: AgentPlugin.new(plugin)
  defp legacy_plugin(module) when is_atom(module), do: AgentPlugin.new(module: module)

  defp legacy_plugin({module, options}) when is_atom(module) and is_list(options) do
    if Keyword.keyword?(options) do
      {as, config} = Keyword.pop(options, :as)
      AgentPlugin.new(module: module, as: as, config: Map.new(config))
    else
      {:error, error("Agent plugin options must be a keyword list")}
    end
  end

  defp legacy_plugin({module, config}) when is_atom(module) and is_map(config),
    do: AgentPlugin.new(module: module, config: config)

  defp legacy_plugin(value), do: AgentPlugin.new(value)

  defp lower_routes(routes) when is_list(routes), do: Router.normalize(routes)
  defp lower_routes(_routes), do: {:error, error("Agent routes must be a list")}

  defp lower_schedules(schedules) when is_list(schedules) do
    schedules
    |> Enum.with_index()
    |> map_list(fn
      {%AgentSchedule{} = schedule, _index} -> AgentSchedule.new(schedule)
      {{cron, signal_type}, index} -> legacy_schedule(cron, signal_type, [], index)
      {{cron, signal_type, options}, index} -> legacy_schedule(cron, signal_type, options, index)
      {schedule, _index} -> AgentSchedule.new(schedule)
    end)
  end

  defp lower_schedules(_schedules), do: {:error, error("Agent schedules must be a list")}

  defp legacy_schedule(cron, signal_type, options, index) when is_list(options) do
    candidate = Keyword.get(options, :job_id, "schedule_#{index}") |> to_string()

    name =
      case Jido.Util.validate_name(candidate) do
        {:ok, valid_name} -> valid_name
        {:error, _error} -> "schedule_#{index}"
      end

    AgentSchedule.new(
      name: name,
      cron_expression: cron,
      signal_type: signal_type,
      timezone: Keyword.get(options, :timezone, "Etc/UTC"),
      data: Keyword.get(options, :data, %{})
    )
  end

  defp legacy_schedule(_cron, _signal_type, _options, _index),
    do: {:error, error("Agent schedule options must be a keyword list")}

  defp map_list(values, function) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case function.(value) do
        {:ok, lowered} -> {:cont, {:ok, [lowered | acc]}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
    |> then(fn
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, _error} = error -> error
    end)
  end

  defp entity_path(%Plugin{}, indexes), do: {:plugins, indexes.plugins}
  defp entity_path(%Route{}, indexes), do: {:routes, indexes.routes}
  defp entity_path(%Schedule{}, indexes), do: {:schedules, indexes.schedules}

  defp source_location(entity, default_file) do
    annotation = annotation_map(Spark.Dsl.Entity.anno(entity))
    explicit = Map.get(entity, :__source__, %{})
    location = Map.merge(annotation, explicit)

    if is_binary(default_file), do: Map.put_new(location, :file, default_file), else: location
  end

  defp annotation_map(nil), do: %{}

  defp annotation_map(annotation) do
    %{}
    |> maybe_put(:line, :erl_anno.line(annotation))
    |> maybe_put(:column, :erl_anno.column(annotation))
  end

  defp maybe_put(map, _key, :undefined), do: map
  defp maybe_put(map, _key, 0), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp error(message, details \\ %{}),
    do: Error.validation_error(message, details: details)
end
