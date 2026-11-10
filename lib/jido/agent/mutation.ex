defmodule Jido.Agent.Mutation do
  @moduledoc false
  alias Jido.Agent.{Diff, Directive, Extension, Plugin, Route, Schema, Topology, Validation}
  alias Jido.Agent.Directive.Kind
  alias Jido.Error
  alias Jido.Plugin.Normalizer

  @modules Kind.mutation_modules()

  def mutation?(%{__struct__: module}), do: module in @modules
  def mutation?(_), do: false

  def apply(agent, state, directives) do
    apply_changes(agent, state, directives, Enum.filter(directives, &mutation?/1))
  end

  # Runner checks complete state before this internal composition step.
  defp apply_changes(agent, state, _directives, []), do: {:ok, %{agent | state: state}}

  defp apply_changes(agent, state, directives, changes) do
    with {:ok, candidate, _diff} <- __MODULE__.apply(%{agent | state: state}, changes),
         :ok <- validate_effects(agent, candidate, directives),
         do: {:ok, candidate}
  end

  @doc "Checks bindings without changing the authored definition."
  def bind(agent) do
    with {:ok, _} <- Topology.bind(agent, agent.state, &Validation.resolve/2), do: {:ok, agent}
  end

  def apply(agent, directives) do
    with {:ok, _} <- Validation.validate(agent),
         {:ok, changes} <- Error.prefix_result_path(Schema.list(directives, &validate/1), :directives),
         {:ok, candidate} <- edit_all(agent, changes),
         {:ok, candidate} <- normalize_routes(candidate),
         {:ok, candidate} <- Validation.validate(candidate) do
      {:ok, candidate, Diff.between(agent, candidate)}
    end
  end

  # Operation validation does not resolve cross-references until the final candidate.
  def validate(%{__struct__: module} = directive) when module in @modules do
    case operation(directive) do
      {:edit, collection, op, key, value} ->
        with :ok <- valid_key(collection, key),
             :ok <- valid_value(collection, op, value),
             do: {:ok, directive}

      {:set, :routes, values} ->
        with {:ok, _} <- Schema.list(values, &Route.normalize(&1, false)),
             do: {:ok, directive}

      {:reorder, paths} ->
        with {:ok, _} <-
               Schema.list(paths, fn path -> with :ok <- Schema.path(path), do: {:ok, path} end),
             :ok <- Schema.unique(paths, & &1),
             do: {:ok, directive}

      {:topology, topology} ->
        with {:ok, _} <- Topology.validate(topology),
             :ok <- Schema.static(topology),
             do: {:ok, directive}

      {:plugin, change} ->
        validate_plugin(change, directive)
    end
  end

  def validate(_), do: Error.validation_result(:invalid_mutation, [], "Expected an Agent mutation Directive")

  defp edit_all(agent, changes) do
    Enum.reduce_while(Enum.with_index(changes), {:ok, agent}, fn {directive, index}, {:ok, current} ->
      case edit(current, operation(directive)) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, Error.prefix_result_path(error, [:directives, index])}
      end
    end)
  end

  defp edit(agent, {:topology, topology}) do
    with {:ok, topology} <- Topology.validate(topology),
         do: {:ok, %{agent | topology: topology}}
  end

  defp edit(agent, {:plugin, change}), do: edit_plugin(agent, change)
  defp edit(agent, {:set, :routes, routes}), do: {:ok, %{agent | routes: routes}}

  defp edit(agent, {:reorder, paths}) do
    if MapSet.new(paths) == MapSet.new(Enum.map(agent.routes, & &1.path)) do
      by_path = Map.new(agent.routes, &{&1.path, &1})
      {:ok, %{agent | routes: Enum.map(paths, &Map.fetch!(by_path, &1))}}
    else
      error(:invalid_route_order)
    end
  end

  defp edit(agent, {:edit, collection, op, key, value}) do
    entries =
      if collection == :routes, do: agent.routes, else: Map.get(agent.topology, collection, [])

    index = Enum.find_index(entries, &(identity(collection, &1) == key))

    cond do
      op == :add and index != nil ->
        error(:already_exists, %{collection: collection, key: key})

      op != :add and index == nil ->
        error(:not_found, %{collection: collection, key: key})

      true ->
        next =
          case op do
            :add -> entries ++ [value]
            :remove -> List.delete_at(entries, index)
            :replace -> List.replace_at(entries, index, value)
            :update -> List.update_at(entries, index, &Map.merge(&1, value))
          end

        if collection == :routes,
          do: {:ok, %{agent | routes: next}},
          else: {:ok, %{agent | topology: Map.put(agent.topology, collection, next)}}
    end
  end

  defp identity(:routes, value), do: value.path
  defp identity(:agents, value), do: value.name
  defp identity(:connections, value), do: {value.from, value.to, value.path}
  defp endpoint(value) when is_atom(value), do: %{kind: :agent, name: value}
  defp endpoint(value), do: value

  defp operation(%Directive.TopologySet{topology: value}), do: {:topology, value}
  defp operation(%Directive.RoutesSet{routes: values}), do: {:set, :routes, values}
  defp operation(%Directive.RoutesReorder{paths: paths}), do: {:reorder, paths}

  defp operation(%Directive.AgentAdd{} = d),
    do: {:edit, :agents, :add, d.name, Map.from_struct(d)}

  defp operation(%Directive.AgentReplace{} = d),
    do: {:edit, :agents, :replace, d.name, Map.from_struct(d)}

  defp operation(%Directive.AgentUpdate{} = d), do: {:edit, :agents, :update, d.name, d.changes}
  defp operation(%Directive.AgentRemove{name: name}), do: {:edit, :agents, :remove, name, nil}
  defp operation(%Directive.RouteAdd{} = d), do: route_value(:add, d)
  defp operation(%Directive.RouteReplace{} = d), do: route_value(:replace, d)
  defp operation(%Directive.RouteUpdate{} = d), do: {:edit, :routes, :update, d.path, d.changes}
  defp operation(%Directive.RouteRemove{path: path}), do: {:edit, :routes, :remove, path, nil}
  defp operation(%Directive.ConnectionAdd{} = d), do: connection_value(:add, d)
  defp operation(%Directive.ConnectionReplace{} = d), do: connection_value(:replace, d)

  defp operation(%Directive.ConnectionUpdate{} = d),
    do: {:edit, :connections, :update, {endpoint(d.from), endpoint(d.to), d.path}, d.changes}

  defp operation(%Directive.ConnectionRemove{} = d),
    do: {:edit, :connections, :remove, {endpoint(d.from), endpoint(d.to), d.path}, nil}

  defp operation(%Directive.PluginAdd{} = d),
    do: {:plugin, Map.merge(Map.from_struct(d), %{op: :add, migrate: nil, state: nil})}

  defp operation(%Directive.PluginConfigure{} = d),
    do: {:plugin, Map.merge(Map.from_struct(d), %{op: :configure, initial: :default, state: nil})}

  defp operation(%Directive.PluginRemove{} = d),
    do: {:plugin, Map.merge(Map.from_struct(d), %{op: :remove, options: [], initial: :default, migrate: nil})}

  defp route_value(op, d) do
    handler = if is_atom(d.handler), do: %{kind: :executable, target: d.handler}, else: d.handler

    value = %{Map.from_struct(d) | handler: handler}
    value = if is_nil(value.state), do: Map.delete(value, :state), else: value

    {:edit, :routes, op, d.path, value}
  end

  defp connection_value(op, d) do
    value = %{Map.from_struct(d) | from: endpoint(d.from), to: endpoint(d.to)}
    {:edit, :connections, op, {value.from, value.to, d.path}, value}
  end

  defp valid_key(:agents, key), do: Schema.name(key)
  defp valid_key(:routes, key), do: Schema.path(key)

  defp valid_key(:connections, {from, to, path}) do
    with :ok <- Schema.plain_map(from), :ok <- Schema.plain_map(to), do: Schema.path(path)
  end

  defp valid_value(_, :remove, _), do: :ok

  defp valid_value(collection, :update, value) do
    allowed =
      case collection do
        :agents -> [:definition, :count, :initial_state]
        :routes -> [:handler, :as, :defaults, :state, :reply]
        :connections -> [:delivery]
      end

    with {:ok, _} <- Schema.fields(value, allowed), :ok <- Schema.static(value), do: :ok
  end

  defp valid_value(collection, _, value) do
    result =
      case collection do
        :routes -> Route.normalize(value, false)
        :agents -> Topology.entry(:agent, value)
        :connections -> Topology.entry(:connect, value)
      end

    with {:ok, _} <- result, :ok <- Schema.static(value), do: :ok
  end

  defp validate_plugin(change, directive) do
    with :ok <- Schema.name(change.module),
         true <- Keyword.keyword?(change.options),
         true <- Enum.uniq(Keyword.keys(change.options)) == Keyword.keys(change.options),
         true <- change.state in [nil, :discard],
         true <- change.initial == :default or match?({:value, _}, change.initial),
         true <-
           change.migrate == nil or
             match?({m, f, args} when is_atom(m) and is_atom(f) and is_list(args), change.migrate),
         :ok <- Schema.static(change) do
      {:ok, directive}
    else
      false -> error(:invalid_plugin_change)
      error -> error
    end
  end

  defp edit_plugin(agent, directive) do
    with {:ok, before} <- Normalizer.normalize_all(Plugin.declarations(agent)) do
      index = Enum.find_index(before, &(&1.module == directive.module))

      cond do
        directive.op == :add and not is_nil(index) ->
          error(:plugin_exists, %{plugin: directive.module})

        directive.op != :add and is_nil(index) ->
          error(:plugin_not_found, %{plugin: directive.module})

        directive.op == :remove ->
          remove_plugin(agent, Enum.at(before, index), directive)

        true ->
          declarations =
            if directive.op == :add,
              do: Plugin.declarations(agent) ++ [{directive.module, directive.options}],
              else:
                List.replace_at(
                  Plugin.declarations(agent),
                  index,
                  {directive.module, directive.options}
                )

          with {:ok, after_specs} <- Normalizer.normalize_all(declarations),
               spec = Enum.find(after_specs, &(&1.module == directive.module)),
               old = if(is_nil(index), do: nil, else: Enum.at(before, index)),
               {:ok, state} <- plugin_state(agent.state, old, spec, directive) do
            with {:ok, next} <- replace_runtime_plugins(agent, declarations),
                 do: {:ok, %{next | state: state}}
          end
      end
    end
  end

  defp remove_plugin(agent, spec, directive) do
    key = state_key(spec)

    if key && agent.state != nil && directive.state != :discard do
      error(:plugin_state_discard_required, %{plugin: spec.module})
    else
      declarations = Enum.reject(Plugin.declarations(agent), &(elem(&1, 0) == spec.module))

      with {:ok, next} <- replace_runtime_plugins(agent, declarations),
           do:
             {:ok,
              %{
                next
                | state:
                    if(key && agent.state != nil,
                      do: Map.delete(agent.state, key),
                      else: agent.state
                    )
              }}
    end
  end

  defp state_key(%{agent: %{state_key: key}}), do: key
  defp state_key(_), do: nil

  defp plugin_state(nil, _old, _spec, _directive), do: {:ok, nil}

  defp plugin_state(state, nil, %{agent: %{state_key: key, state_schema: schema}}, directive)
       when not is_nil(key) do
    initial =
      case directive.initial do
        :default -> %{}
        {:value, value} -> %{key => value}
      end

    with {:ok, value} <- Schema.initialize(Jido.Joi.object(%{key => schema}), initial) do
      if Map.has_key?(state, key),
        do: error(:plugin_state_conflict, %{key: key}),
        else: {:ok, Map.merge(state, value)}
    end
  end

  defp plugin_state(state, nil, _, _), do: {:ok, state}

  defp plugin_state(state, old, spec, directive) do
    old_key = state_key(old)
    new_key = state_key(spec)
    value = if old_key, do: Map.get(state, old_key)

    with {:ok, value} <- migrate(value, directive.migrate),
         true <- old_key == new_key or not is_nil(directive.migrate),
         next = if(old_key, do: Map.delete(state, old_key), else: state),
         next = if(new_key, do: Map.put(next, new_key, value), else: next) do
      {:ok, next}
    else
      false -> error(:plugin_migration_required, %{plugin: spec.module})
      error -> error
    end
  end

  defp migrate(value, nil), do: {:ok, value}

  defp migrate(value, {module, fun, args}) do
    case Kernel.apply(module, fun, [value | args]) do
      {:ok, next} -> {:ok, next}
      {:error, _} = error -> error
      _ -> error(:invalid_plugin_migration)
    end
  rescue
    _ -> error(:plugin_migration_failed)
  catch
    _, _ -> error(:plugin_migration_failed)
  end

  def changed_plugins(before, after_agent, directives \\ []) do
    old = Map.new(Plugin.declarations(before))
    new = Map.new(Plugin.declarations(after_agent))
    configured = for %Directive.PluginConfigure{module: module} <- directives, do: module

    (Map.keys(old) ++ Map.keys(new))
    |> Enum.uniq()
    |> Enum.filter(&(Map.fetch(old, &1) != Map.fetch(new, &1)))
    |> Kernel.++(configured)
    |> Enum.uniq()
  end

  def validate_effects(before, after_agent, directives) do
    changed = changed_plugins(before, after_agent, directives)

    with {:ok, old} <- Normalizer.normalize_all(Plugin.declarations(before)),
         {:ok, new} <- Normalizer.normalize_all(Plugin.declarations(after_agent)) do
      if Enum.any?(directives, fn directive ->
           case Jido.Plugin.directive_owner(old ++ new, directive) do
             %{module: module} -> module in changed
             _ -> false
           end
         end),
         do: error(:plugin_change_with_owned_directive),
         else: :ok
    end
  end

  defp replace_runtime_plugins(agent, declarations) do
    old_modules = Plugin.declarations(agent) |> Keyword.keys()

    with {:ok, added} <-
           Jido.Agent.Schema.list(declarations, fn {module, options} ->
             with {:ok, provider} <- Extension.provider(module),
                  do:
                    {:ok,
                     %{
                       id: provider.id(),
                       provider: provider,
                       vsn: provider.vsn(),
                       data: Map.new(options)
                     }}
           end),
         replacements = Map.new(added, &{&1.provider, &1}),
         retained =
           Enum.flat_map(agent.plugins, fn entry ->
             if entry.provider in old_modules,
               do: List.wrap(Map.get(replacements, entry.provider)),
               else: [entry]
           end),
         appended = Enum.reject(added, &(&1.provider in old_modules)),
         {:ok, entries} <- Extension.normalize(retained ++ appended),
         do: {:ok, %{agent | plugins: entries}}
  end

  defp normalize_routes(agent) do
    with {:ok, routes} <-
           Schema.list(agent.routes, fn
             %{handler: target} = route when is_atom(target) ->
               with {:ok, handler} <- Route.executable(target),
                    do: {:ok, %{route | handler: handler}}

             %{handler: %{kind: :executable, target: target}} = route ->
               with {:ok, handler} <- Route.executable(target),
                    do: {:ok, %{route | handler: handler}}

             route ->
               {:ok, route}
           end),
         {:ok, definition} <-
           Validation.define(%{agent | id: nil, state: nil, routes: routes}) do
      {:ok, %{definition | id: agent.id, state: agent.state}}
    end
  end

  defp error(code, details \\ %{}), do: Error.validation_result(code, [], "Agent mutation failed", details)
end
