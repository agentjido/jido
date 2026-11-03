defmodule Jido.Agent.Validation do
  @moduledoc false
  alias Jido.Agent.{Extension, Plugin, Route, Topology}
  alias Jido.Error
  alias Jido.Joi
  alias Jido.Signal
  alias Jido.Signal.Context, as: SignalContext

  @fields [
    :id,
    :state,
    :module,
    :name,
    :description,
    :vsn,
    :schema,
    :initial_state,
    :metadata,
    :signal_source,
    :routes,
    :topology,
    :plugins
  ]

  def attrs(value) do
    case to_attrs(value, :reject) do
      {:ok, attrs} -> {:ok, attrs}
      :error when is_list(value) -> authoring_error("Expected unique keyword options", %{value: value})
      :error -> authoring_error("Expected a map or keyword list", %{value: value})
    end
  end

  # Public boundaries keep their own duplicate policy and error context.
  def to_attrs(value, duplicates \\ :last)
  def to_attrs(value, _duplicates) when is_map(value) and not is_struct(value), do: {:ok, value}

  def to_attrs(value, duplicates) when is_list(value) do
    if Keyword.keyword?(value) and
         (duplicates == :last or Enum.uniq(Keyword.keys(value)) == Keyword.keys(value)),
       do: {:ok, Map.new(value)},
       else: :error
  end

  def to_attrs(_value, _duplicates), do: :error

  def keys(map, allowed) do
    case Map.keys(map) -- allowed do
      [] -> :ok
      unknown -> authoring_error("Unknown authoring fields", %{keys: unknown})
    end
  end

  def traverse(values, fun), do: traverse(values, fun, [])
  defp traverse([], _fun, acc), do: {:ok, Enum.reverse(acc)}

  defp traverse([value | tail], fun, acc) do
    case fun.(value) do
      {:ok, result} -> traverse(tail, fun, [result | acc])
      {:error, _error} = error -> error
    end
  end

  defp traverse(_tail, _fun, _acc), do: authoring_error("Expected a proper list")

  def authoring_error(message, details \\ %{}),
    do: {:error, Error.validation_error(message, kind: :config, details: details)}

  def fields(value, allowed, defaults \\ %{}) do
    with :ok <- plain_map(value),
         [] <- Map.keys(value) -- allowed do
      {:ok, Map.merge(defaults, value)}
    else
      keys when is_list(keys) -> Error.validation_result(:unknown_fields, [], "Unknown fields", %{keys: keys})
      error -> error
    end
  end

  def plain_map(value) when is_map(value) and not is_struct(value), do: :ok
  def plain_map(_), do: Error.validation_result(:invalid_map, [], "Expected a plain Map")

  def nonempty(value) when is_binary(value) and byte_size(value) > 0, do: :ok
  def nonempty(_), do: Error.validation_result(:invalid_string, [], "Expected a nonempty string")

  def name(value) when is_atom(value) and value not in [nil, true, false], do: :ok
  def name(_), do: Error.validation_result(:invalid_name, [], "Expected a name atom")

  def positive(value) when is_integer(value) and value > 0, do: :ok
  def positive(_), do: Error.validation_result(:invalid_positive, [], "Expected a positive integer")

  def list(values, fun), do: walk(values, fun, 0, [])
  defp walk([], _fun, _index, acc), do: {:ok, Enum.reverse(acc)}

  defp walk([value | tail], fun, index, acc) do
    with {:ok, value} <- Error.prefix_result_path(fun.(value), [index]),
         do: walk(tail, fun, index + 1, [value | acc])
  end

  defp walk(_, _, _, _), do: Error.validation_result(:invalid_list, [], "Expected a proper list")

  def unique(values, key) do
    keys = Enum.map(values, key)

    if Enum.uniq(keys) == keys,
      do: :ok,
      else: Error.validation_result(:duplicate, [], "Duplicate declaration", %{values: keys})
  end

  def static(value) do
    case Jido.Codec.validate_static(value) do
      :ok ->
        :ok

      {:error, _reason} ->
        Error.validation_result(:live_value, [], "Authoring data cannot contain live values")
    end
  end

  def schema(schema) do
    case {Joi.Schema.kind(schema), Joi.Schema.fields(schema)} do
      {:map, {:ok, fields}} when is_list(fields) -> static_schema(schema)
      _ -> Error.validation_result(:invalid_schema, [], "Expected a static Joi object schema")
    end
  end

  defp static_schema(%{__struct__: _type} = value) do
    if Joi.Schema.coerce?(value) or
         Joi.Schema.forbidden_state_type?(value) or
         Enum.any?(Joi.Schema.effects(value), &Joi.Schema.transform_effect?/1) do
      Error.validation_result(:invalid_schema, [], "State schemas cannot convert values")
    else
      static_schema(Map.from_struct(value))
    end
  end

  defp static_schema(value) when is_map(value),
    do: schema_items(Enum.flat_map(value, fn {k, v} -> [k, v] end))

  defp static_schema(value) when is_list(value), do: schema_items(value)
  defp static_schema(value) when is_tuple(value), do: schema_items(Tuple.to_list(value))
  defp static_schema(value), do: static(value)

  defp schema_items(values) do
    with {:ok, _} <-
           list(values, fn value -> with :ok <- static_schema(value), do: {:ok, value} end),
         do: :ok
  end

  def initialize(schema, state) do
    with :ok <- plain_map(state),
         do: parse_value(Joi.Schema.put_unrecognized_keys(schema, :error), state)
  end

  def parse_value(schema, input) do
    case Joi.initialize(schema, input) do
      {:ok, initialized} ->
        {:ok, initialized}

      {:error, issues} ->
        if Enum.any?(issues, &Joi.Error.changed_value?/1) do
          Error.validation_result(
            :state_conversion,
            [],
            "State initialization can add defaults but cannot convert supplied values"
          )
        else
          Error.validation_result(:invalid_state, [], "State does not match its schema", %{issues: issues})
        end
    end
  end

  def complete(schema, state) do
    with :ok <- plain_map(state) do
      case Joi.validate(Joi.Schema.put_unrecognized_keys(schema, :error), state) do
        :ok ->
          :ok

        {:error, issues} ->
          cond do
            Enum.any?(issues, &Joi.Error.changed_value?/1) ->
              Error.validation_result(:state_conversion, [], "Validation cannot change stored state")

            Enum.any?(issues, &(Joi.Error.code(&1) == :required)) ->
              Error.validation_result(:incomplete_state, [], "State does not match its schema", %{
                issues: issues
              })

            true ->
              Error.validation_result(:invalid_state, [], "State does not match its schema", %{issues: issues})
          end
      end
    end
  end

  def path(value) when is_binary(value) do
    case Jido.Signal.Router.Route.validate_path(value, []) do
      :ok -> :ok
      {:error, _} -> Error.validation_result(:invalid_path, [], "Invalid Signal path", %{path: value})
    end
  end

  def path(_), do: Error.validation_result(:invalid_path, [], "Expected a Signal path string")

  def exact(value) do
    with :ok <- path(value) do
      if wildcard?(value),
        do: Error.validation_result(:wildcard_type, [], "Expected an exact Signal type"),
        else: :ok
    end
  end

  def wildcard?(value), do: String.contains?(value, "*")
  def matches?(type, path), do: Jido.Signal.Router.matches?(type, path)

  def state_schema(%Jido.Agent{} = agent) do
    with {:ok, schema} <-
           Jido.Agent.Plugin.compose_schema(agent.schema, Jido.Agent.runtime_plugins(agent)),
         :ok <- Error.prefix_result_path(schema(schema), :schema),
         do: {:ok, schema}
  end

  def define(input, opts \\ [])
  def define(%Jido.Agent{} = input, opts), do: define(Map.from_struct(input), opts)

  def define(input, opts) do
    related? = Keyword.get(opts, :related?, true)

    with {:ok, definition} <- fields(input, @fields, Jido.Agent.__defaults__()),
         :ok <- fields(definition),
         {:ok, plugins} <- Error.prefix_result_path(Extension.normalize(definition.plugins), :plugins),
         {:ok, route_contributions} <-
           Error.prefix_result_path(Extension.route_contributions(plugins), :plugins),
         {:ok, routes} <-
           Error.prefix_result_path(list(definition.routes, &Route.normalize(&1, related?)), :routes),
         {:ok, routes} <- materialize_routes(routes, route_contributions, related?),
         :ok <- Error.prefix_result_path(Plugin.validate_route_contract(routes, plugins), :routes),
         :ok <- Error.prefix_result_path(unique(Enum.reject(routes, &is_nil(&1.as)), & &1.as), :routes),
         :ok <- reply_source(routes, definition.signal_source, related?),
         definition = %{definition | routes: routes, plugins: plugins},
         {:ok, topology} <-
           Error.prefix_result_path(Topology.normalize(definition.topology, definition, opts), :topology),
         definition = %{definition | topology: topology},
         :ok <- forward_targets(definition),
         :ok <- verify_plugins(plugins, definition, related?),
         :ok <- plugin_schema(definition, related? and Keyword.get(opts, :plugin_schema?, true)) do
      {:ok, struct!(Jido.Agent, definition)}
    else
      {:error, %Error.ValidationError{} = error} ->
        {:error,
         %{
           error
           | details:
               Map.put_new(
                 error.details,
                 :definition,
                 if(is_map(input), do: Map.get(input, :name), else: nil)
               )
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_plugins(plugins, definition, true),
    do: Error.prefix_result_path(Extension.verify(plugins, definition), :plugins)

  defp verify_plugins(_, _, false), do: :ok

  defp materialize_routes(routes, contributions, related?) do
    contributions
    |> Enum.reduce_while({:ok, routes, MapSet.new()}, fn contribution, {:ok, routes, owned_paths} ->
      route_path = [
        :plugins,
        contribution.plugin_index,
        :routes,
        contribution.index
      ]

      case Error.prefix_result_path(Route.normalize(contribution.route, related?), route_path) do
        {:ok, route} ->
          merge_contributed_route(routes, owned_paths, route, contribution.provider)

        {:error, _error} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, routes, _owned_paths} -> {:ok, routes}
      {:error, _error} = error -> error
    end
  end

  defp merge_contributed_route(routes, owned_paths, route, provider) do
    case Enum.find_index(routes, &(&1.path == route.path)) do
      nil ->
        {:cont, {:ok, routes ++ [route], MapSet.put(owned_paths, route.path)}}

      index ->
        existing = Enum.at(routes, index)

        if existing === route and not MapSet.member?(owned_paths, route.path) do
          {:cont, {:ok, routes, MapSet.put(owned_paths, route.path)}}
        else
          {:halt,
           Error.validation_result(
             :plugin_route_conflict,
             [:routes, index],
             "Plugin route conflicts with another Agent route",
             %{path: route.path, provider: provider}
           )}
        end
    end
  end

  defp plugin_schema(fields, true) do
    with {:ok, _schema} <- state_schema(struct!(Jido.Agent, fields)), do: :ok
  end

  defp plugin_schema(_, false), do: :ok

  defp reply_source(routes, signal_source, related?) do
    if related? and is_nil(signal_source) and Enum.any?(routes, &(!is_nil(&1.reply))),
      do:
        Error.validation_result(
          :reply_source_required,
          [:signal_source],
          "A reply route requires an Agent signal source"
        ),
      else: :ok
  end

  def validate(%Jido.Agent{id: nil, state: nil} = value), do: validate_definition(value)
  def validate(%Jido.Agent{} = value), do: validate_instance(value)
  def validate(_), do: Error.validation_result(:invalid_agent, [], "Expected a Jido.Agent struct")

  def normalize_context(nil), do: {:ok, %{}}

  def normalize_context(context) do
    case to_attrs(context) do
      {:ok, context} -> {:ok, context}
      :error -> invalid_command("Agent caller context must be a map or keyword list", %{context: context})
    end
  end

  def normalize_signal(%Signal{type: type} = signal) when is_binary(type) do
    with {:ok, signal} <- Jido.Joi.parse(Signal.schema(), signal),
         {:ok, extensions} <- SignalContext.normalize(signal.extensions) do
      {:ok, %{signal | extensions: extensions}}
    else
      {:error, issues} -> invalid_command("Agent command Signal is invalid", %{issues: issues})
    end
  end

  def normalize_signal(%Signal{} = signal) do
    {:error, cause} = Jido.Signal.Router.route(Jido.Signal.Router.new!([]), signal)

    {:error,
     Error.routing_error(cause.message,
       target: signal.type,
       details: Map.put(cause.details, :cause, cause)
     )}
  end

  def normalize_signal(value),
    do: invalid_command("Agent command must contain a Jido.Signal", %{signal: value})

  def validate_caller_context(context) when is_map(context) and not is_struct(context) do
    reserved =
      Enum.filter(
        [
          :agent_id,
          :agent_module,
          :agent_signal_source,
          :agent_state,
          :agent_topology,
          :signal,
          :plugin_inputs,
          :__jido_exec_durable__,
          :__jido_wait_host__,
          :__jido_wait_result__
        ],
        &Map.has_key?(context, &1)
      )

    if reserved == [],
      do: :ok,
      else: invalid_command("Agent command context contains reserved keys", %{keys: reserved})
  end

  def validate_caller_context(context),
    do: invalid_command("Agent command context must be a map", %{context: context})

  def validate_definition(value, opts \\ [])

  def validate_definition(%Jido.Agent{} = value, opts) do
    with {:ok, normalized} <- define(value, opts) do
      if normalized === value,
        do: {:ok, value},
        else: Error.validation_result(:not_canonical, [], "Definition must contain its normalized fields")
    end
  end

  def validate_definition(_, _opts),
    do: Error.validation_result(:definition_required, [], "Expected a definition with nil id and state")

  def validate_instance(value) do
    with {:ok, agent, _specs, _schema} <- validate_instance_with_plugins(value), do: {:ok, agent}
  end

  def instantiate(source, opts),
    do: instantiate(source, opts, %{parent_id: nil, member: nil, slot: nil})

  def instantiate(source, opts, parent_context) do
    with {:ok, definition} <- resolve(source),
         {:ok, opts} <- options(opts, [:id, :state]),
         :ok <- Error.prefix_result_path(nonempty(opts[:id]), :id),
         state = Map.get(opts, :state, %{}),
         :ok <- Error.prefix_result_path(plain_map(state), :state),
         {:ok, schema} <- Jido.Agent.Validation.state_schema(definition),
         context = Map.put(parent_context, :id, opts.id),
         state = Map.merge(definition.initial_state, state),
         {:ok, state} <- initialize(definition, state, context),
         {:ok, state} <- Error.prefix_result_path(initialize(schema, state), :state),
         {:ok, _} <- Topology.bind(definition, state),
         do: {:ok, %{definition | id: opts.id, state: state}}
  end

  defp initialize(%{module: module}, state, context) do
    if module not in [nil, true, false] and Code.ensure_loaded?(module) and
         function_exported?(module, :initialize, 2) do
      case Jido.Agent.Runner.invoke(module, :initialize, [state, context]) do
        {:ok, state} ->
          with :ok <- Error.prefix_result_path(plain_map(state), :initialize), do: {:ok, state}

        {:error, %{__exception__: true}} = error ->
          error

        {:error, reason} ->
          initialize_error(%{reason: reason})

        result ->
          initialize_error(%{result: result})
      end
    else
      {:ok, state}
    end
  end

  defp initialize_error(details),
    do: Error.validation_result(:initialize_failed, [:initialize], "Agent initialize/2 failed", details)

  def resolve(%Jido.Agent{} = definition), do: validate_definition(definition)

  def resolve(module) when is_atom(module) and module not in [nil, true, false] do
    if Code.ensure_loaded?(module) and function_exported?(module, :definition, 0),
      do: resolve_module(module),
      else:
        Error.validation_result(:unresolved_definition, [], "Agent definition module is not available", %{
          module: module
        })
  end

  def resolve(_),
    do: Error.validation_result(:definition_required, [], "Expected an Agent definition or module")

  defp resolve_module(module) do
    validate_definition(module.definition())
  rescue
    reason -> definition_failed(module, :error, reason)
  catch
    kind, reason -> definition_failed(module, kind, reason)
  end

  defp definition_failed(module, kind, reason),
    do:
      Error.validation_result(:definition_failed, [], "Agent module definition failed", %{
        module: module,
        kind: kind,
        reason: reason
      })

  def loaded_agent_module?(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :definition, 0)

  defp dependencies(agent) do
    with {:ok, specs} <- Jido.Plugin.Normalizer.normalize_all(Jido.Agent.runtime_plugins(agent)),
         {:ok, schema} <- Jido.Agent.Plugin.compose_schema_from_specs(agent.schema, specs),
         :ok <- Error.prefix_result_path(schema(schema), :schema),
         do: {:ok, specs, schema}
  end

  def validate_instance_with_plugins(%Jido.Agent{} = value) do
    with :ok <- Error.prefix_result_path(nonempty(value.id), :id),
         {:ok, definition} <-
           validate_definition(Jido.Agent.definition(value), plugin_schema?: false),
         {:ok, specs, schema} <- dependencies(definition),
         :ok <- Error.prefix_result_path(complete(schema, value.state), :state),
         {:ok, _} <- Topology.bind(definition, value.state),
         do: {:ok, value, specs, schema}
  end

  def validate_instance_with_plugins(_),
    do: Error.validation_result(:instance_required, [], "Expected an Agent instance")

  def options(opts, allowed) when is_list(opts) do
    if Keyword.keyword?(opts) and
         length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))),
       do: fields(Map.new(opts), allowed),
       else: Error.validation_result(:invalid_options, [], "Expected unique keyword options")
  end

  def options(opts, allowed), do: fields(opts, allowed)

  defp invalid_command(message, details),
    do: {:error, Error.validation_error(message, kind: :config, details: details)}

  defp fields(definition) do
    with :ok <- neutral(definition),
         :ok <- Error.prefix_result_path(nonempty(definition[:name]), :name),
         :ok <- optional_module(definition.module),
         :ok <- optional_description(definition.description),
         :ok <- Error.prefix_result_path(positive(definition.vsn), :vsn),
         :ok <- Error.prefix_result_path(schema(definition.schema), :schema),
         :ok <- Error.prefix_result_path(plain_map(definition.initial_state), :initial_state),
         :ok <- Error.prefix_result_path(static(definition.initial_state), :initial_state),
         :ok <- Error.prefix_result_path(plain_map(definition.metadata), :metadata),
         :ok <- Error.prefix_result_path(static(definition.metadata), :metadata),
         :ok <- source(definition.signal_source),
         do: :ok
  end

  defp neutral(%{id: nil, state: nil}), do: :ok
  defp neutral(_), do: Error.validation_result(:definition_required, [], "Definition id and state must be nil")
  defp optional_module(nil), do: :ok
  defp optional_module(module), do: Error.prefix_result_path(name(module), :module)
  defp optional_description(nil), do: :ok
  defp optional_description(value) when is_binary(value), do: :ok

  defp optional_description(_),
    do: Error.validation_result(:invalid_description, :description, "Expected a description string or nil")

  defp source(nil), do: :ok
  defp source(value), do: Error.prefix_result_path(nonempty(value), :signal_source)

  defp forward_targets(definition) do
    names = MapSet.new(definition.topology.agents, & &1.name)

    definition.routes
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn
      {%{handler: %{kind: :forward, target: %{kind: :agent, name: name}}}, index}, :ok ->
        if MapSet.member?(names, name) do
          {:cont, :ok}
        else
          {:halt,
           Error.validation_result(
             :unknown_forward_target,
             [:routes, index, :handler, :target],
             "Forward target is not a declared Agent member",
             %{name: name}
           )}
        end

      {_route, _index}, :ok ->
        {:cont, :ok}
    end)
  end
end
