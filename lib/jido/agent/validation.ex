defmodule Jido.Agent.Validation do
  @moduledoc false
  alias Jido.Agent.{Extension, Plugin, Route, Topology}
  alias Jido.Error
  alias Jido.Signal
  alias Jido.Signal.Context, as: SignalContext
  import Jido.Agent.Schema

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

  def state_schema(agent) do
    if agent?(agent) do
      with {:ok, schema} <- Plugin.compose_schema(agent.schema, Plugin.declarations(agent)),
           :ok <- Error.prefix_result_path(schema(schema), :schema),
           do: {:ok, schema}
    else
      Error.validation_result(:invalid_agent, [], "Expected a Jido.Agent struct")
    end
  end

  def define(input, opts \\ [])

  def define(input, opts) do
    input = if agent?(input), do: Map.from_struct(input), else: input
    related? = Keyword.get(opts, :related?, true)

    with {:ok, definition} <- fields(input, @fields, defaults()),
         :ok <- fields(definition),
         {:ok, plugins} <- Error.prefix_result_path(Extension.normalize(definition.plugins), :plugins),
         {:ok, route_contributions} <-
           Error.prefix_result_path(Extension.route_contributions(plugins), :plugins),
         {:ok, routes} <-
           Error.prefix_result_path(list(definition.routes, &Route.normalize(&1, related?)), :routes),
         {:ok, routes} <- materialize_routes(routes, route_contributions, related?),
         :ok <- Error.prefix_result_path(Plugin.validate_route_contract(routes, plugins), :routes),
         :ok <- Error.prefix_result_path(unique(routes, &Route.identity/1), :routes),
         :ok <- Error.prefix_result_path(unique(Enum.reject(routes, &is_nil(&1.as)), & &1.as), :routes),
         :ok <- reply_source(routes, definition.signal_source, related?),
         definition = %{definition | routes: routes, plugins: plugins},
         {:ok, topology} <-
           Error.prefix_result_path(
             Topology.normalize(definition.topology, definition, opts, &__MODULE__.define/2),
             :topology
           ),
         definition = %{definition | topology: topology},
         :ok <- forward_targets(definition),
         :ok <- verify_plugins(plugins, definition, related?),
         :ok <- plugin_schema(definition, related? and Keyword.get(opts, :plugin_schema?, true)) do
      {:ok, struct!(agent_module(), definition)}
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
    with {:ok, _schema} <- state_schema(struct!(agent_module(), fields)), do: :ok
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

  def validate(%{id: nil, state: nil} = value) do
    if agent?(value),
      do: validate_definition(value),
      else: Error.validation_result(:invalid_agent, [], "Expected a Jido.Agent struct")
  end

  def validate(value) do
    if agent?(value),
      do: validate_instance(value),
      else: Error.validation_result(:invalid_agent, [], "Expected a Jido.Agent struct")
  end

  def normalize_context(nil), do: {:ok, %{}}

  def normalize_context(context) do
    case to_attrs(context) do
      {:ok, context} -> {:ok, context}
      :error -> invalid_command("Agent caller context must be a map or keyword list", %{context: context})
    end
  end

  def normalize_input(nil), do: {:ok, %{}}
  def normalize_input(value) when is_map(value), do: {:ok, value}

  def normalize_input(value) when is_list(value) do
    if Keyword.keyword?(value), do: {:ok, Map.new(value)}, else: {:error, :invalid_input}
  end

  def normalize_input(_value), do: {:error, :invalid_input}

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

  def validate_definition(value, opts) do
    if agent?(value) do
      with {:ok, normalized} <- define(value, opts) do
        if normalized === value,
          do: {:ok, value},
          else: Error.validation_result(:not_canonical, [], "Definition must contain its normalized fields")
      end
    else
      Error.validation_result(:definition_required, [], "Expected a definition with nil id and state")
    end
  end

  def validate_instance(value) do
    with {:ok, agent, _specs, _schema} <- validate_instance_with_plugins(value), do: {:ok, agent}
  end

  def transition(agent, next_state) do
    with {:ok, agent, _specs, schema} <- validate_instance_with_plugins(agent),
         :ok <- Error.prefix_result_path(complete(schema, next_state), :state) do
      {:ok, %{agent | state: next_state}}
    end
  end

  def instantiate(source, opts),
    do: instantiate(source, opts, %{parent_id: nil, member: nil, slot: nil})

  def instantiate(source, opts, parent_context) do
    with {:ok, definition} <- resolve(source),
         {:ok, opts} <- options(opts, [:id, :state]),
         :ok <- Error.prefix_result_path(nonempty(opts[:id]), :id),
         state = Map.get(opts, :state, %{}),
         :ok <- Error.prefix_result_path(plain_map(state), :state),
         {:ok, schema} <- state_schema(definition),
         context = Map.put(parent_context, :id, opts.id),
         state = Map.merge(definition.initial_state, state),
         {:ok, state} <- initialize(definition, state, context),
         {:ok, state} <- Error.prefix_result_path(initialize(schema, state), :state),
         {:ok, _} <- Topology.bind(definition, state, &__MODULE__.resolve/2),
         do: {:ok, %{definition | id: opts.id, state: state}}
  end

  defp initialize(%{module: module}, state, context) do
    if module not in [nil, true, false] and Code.ensure_loaded?(module) and
         function_exported?(module, :initialize, 2) do
      case Jido.Agent.Callback.invoke(module, :initialize, [state, context]) do
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

  def resolve(value), do: resolve(value, [])

  def resolve(%{__struct__: _module} = definition, opts) do
    if agent?(definition),
      do: validate_definition(definition, opts),
      else: Error.validation_result(:definition_required, [], "Expected an Agent definition or module")
  end

  def resolve(module, opts) when is_atom(module) and module not in [nil, true, false] do
    if Code.ensure_loaded?(module) and function_exported?(module, :definition, 0),
      do: resolve_module(module, opts),
      else:
        Error.validation_result(:unresolved_definition, [], "Agent definition module is not available", %{
          module: module
        })
  end

  def resolve(_, _opts),
    do: Error.validation_result(:definition_required, [], "Expected an Agent definition or module")

  defp resolve_module(module, opts) do
    validate_definition(module.definition(), opts)
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
    with {:ok, specs} <- Jido.Plugin.Normalizer.normalize_all(Plugin.declarations(agent)),
         {:ok, schema} <- Plugin.compose_schema_from_specs(agent.schema, specs),
         :ok <- Error.prefix_result_path(schema(schema), :schema),
         do: {:ok, specs, schema}
  end

  def validate_instance_with_plugins(value) do
    if agent?(value) do
      definition = %{value | id: nil, state: nil}

      with :ok <- Error.prefix_result_path(nonempty(value.id), :id),
           {:ok, definition} <- validate_definition(definition, plugin_schema?: false),
           {:ok, specs, schema} <- dependencies(definition),
           :ok <- Error.prefix_result_path(complete(schema, value.state), :state),
           {:ok, _} <- Topology.bind(definition, value.state, &__MODULE__.resolve/2),
           do: {:ok, value, specs, schema}
    else
      Error.validation_result(:instance_required, [], "Expected an Agent instance")
    end
  end

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
