defmodule Jido.Agent.Validation do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.Authoring
  alias Jido.Agent.State
  alias Jido.Error
  alias Jido.Plugin

  @definition_keys [
    :id,
    :module,
    :name,
    :description,
    :max_state_size,
    :schema,
    :plugins,
    :state,
    :routes,
    :metadata
  ]

  @instance_keys [:id, :state]

  @doc false
  @spec new(map() | keyword() | Agent.t()) ::
          {:ok, Agent.t()} | {:error, Exception.t()}
  def new(%Agent{} = agent), do: validate_definition(agent)

  def new(attrs) when is_list(attrs) do
    with {:ok, attrs} <- normalize_attrs(attrs, :definition) do
      new(attrs)
    end
  end

  def new(%{} = attrs) do
    with :ok <- known_keys(attrs),
         :ok <- reject_instance_data(attrs),
         {:ok, agent} <- build_definition(attrs) do
      {:ok, agent}
    end
  end

  def new(value),
    do: invalid("Agent definition must be a map or keyword list", %{value: value})

  @doc false
  @spec instantiate(Agent.t(), map() | keyword()) ::
          {:ok, Agent.t()} | {:error, Exception.t()}
  def instantiate(%Agent{} = definition, overrides) do
    with {:ok, definition, _plugin_specs, schema} <-
           validate_definition_with_plugins(definition),
         {:ok, agent} <- instantiate_validated(definition, schema, overrides) do
      {:ok, agent}
    end
  end

  def instantiate(value, _overrides),
    do: invalid("Expected a neutral Jido.Agent definition", %{value: value})

  @doc false
  @spec validate(term()) :: {:ok, Agent.t()} | {:error, Exception.t()}
  def validate(%Agent{id: nil, state: nil} = agent), do: validate_definition(agent)

  def validate(%Agent{id: id, state: state} = agent)
      when is_binary(id) and is_map(state) and not is_struct(state),
      do: validate_instance(agent)

  def validate(%Agent{} = agent) do
    invalid("Agent must be a complete definition or instance", %{
      id: agent.id,
      state: agent.state
    })
  end

  def validate(value), do: invalid("Expected a Jido.Agent value", %{value: value})

  @doc false
  @spec validate_definition(term()) :: {:ok, Agent.t()} | {:error, Exception.t()}
  def validate_definition(%Agent{id: nil, state: nil} = agent) do
    with {:ok, agent, _plugin_specs, _schema} <- validate_common(agent) do
      {:ok, %{agent | id: nil, state: nil}}
    end
  end

  def validate_definition(%Agent{} = agent) do
    invalid("Agent definition cannot contain instance identity or state", %{
      id: agent.id,
      state: agent.state
    })
  end

  def validate_definition(value),
    do: invalid("Expected a neutral Jido.Agent definition", %{value: value})

  @doc false
  @spec validate_instance(term()) :: {:ok, Agent.t()} | {:error, Exception.t()}
  def validate_instance(%Agent{} = agent) do
    with {:ok, agent, _plugin_specs, schema} <- validate_common(agent) do
      validate_instance_data(agent, schema)
    end
  end

  def validate_instance(value),
    do: invalid("Expected a Jido.Agent instance", %{value: value})

  @doc false
  @spec definition_from_module(module(), map() | keyword()) ::
          {:ok, Agent.t()} | {:error, Exception.t()}
  def definition_from_module(module, definition) when is_atom(module) do
    with {:ok, definition} <- normalize_attrs(definition, :definition) do
      definition
      |> Map.put(:module, module)
      |> new()
    end
  end

  @doc false
  @spec new_from_module(module(), map() | keyword(), map() | keyword()) ::
          {:ok, Agent.t()} | {:error, Exception.t()}
  def new_from_module(module, definition, overrides) when is_atom(module) do
    with {:ok, attrs} <- normalize_attrs(definition, :definition),
         attrs = Map.put(attrs, :module, module),
         :ok <- known_keys(attrs),
         :ok <- reject_instance_data(attrs),
         {:ok, definition, _plugin_specs, schema} <- build_definition_with_plugins(attrs),
         {:ok, agent} <- instantiate_validated(definition, schema, overrides) do
      {:ok, agent}
    end
  end

  defp build_definition(attrs) do
    with {:ok, agent, _plugin_specs, _schema} <- build_definition_with_plugins(attrs) do
      {:ok, agent}
    end
  end

  defp build_definition_with_plugins(attrs) do
    agent = %Agent{
      id: nil,
      module: Map.get(attrs, :module, Agent),
      name: Map.get(attrs, :name),
      description: Map.get(attrs, :description),
      max_state_size: Map.get(attrs, :max_state_size),
      schema: Map.get(attrs, :schema, Zoi.object(%{})),
      plugins: Map.get(attrs, :plugins, []),
      state: nil,
      routes: Map.get(attrs, :routes, []),
      metadata: Map.get(attrs, :metadata, %{})
    }

    validate_common(agent)
  end

  defp validate_common(%Agent{} = agent) do
    with {:ok, name} <- field(:name, agent.name),
         {:ok, description} <- field(:description, agent.description),
         :ok <- validate_module(agent.module),
         :ok <- Jido.Agent.StateBudget.validate_limit(agent.max_state_size),
         {:ok, plugin_specs} <- Plugin.normalize_all(agent.plugins),
         :ok <- State.validate_schema(agent.schema),
         {:ok, complete_schema} <- Plugin.compose_schema(agent.schema, plugin_specs),
         {:ok, plugins} <- Plugin.canonical_declarations(plugin_specs),
         {:ok, routes} <- validate_routes(agent.routes),
         {:ok, metadata} <- field(:metadata, agent.metadata) do
      validated = %{
        agent
        | name: name,
          description: description,
          plugins: plugins,
          routes: routes,
          metadata: metadata
      }

      {:ok, validated, plugin_specs, complete_schema}
    end
  end

  defp validate_definition_with_plugins(%Agent{id: nil, state: nil} = definition),
    do: validate_common(definition)

  defp validate_definition_with_plugins(%Agent{} = definition) do
    invalid("Agent definition cannot contain instance identity or state", %{
      id: definition.id,
      state: definition.state
    })
  end

  defp instantiate_validated(definition, schema, overrides) do
    with {:ok, overrides} <- normalize_attrs(overrides, :instance),
         :ok <- validate_instance_overrides(overrides),
         {:ok, id} <- instance_id(Map.get(overrides, :id)),
         {:ok, state} <- initial_state(schema, Map.get(overrides, :state, %{})) do
      validate_instance_data(%{definition | id: id, state: state}, schema)
    end
  end

  defp validate_instance_data(agent, schema) do
    with {:ok, id} <- validate_id(agent.id),
         {:ok, state} <- State.validate(agent.state, schema) do
      Jido.Agent.StateBudget.check(%{agent | id: id, state: state})
    end
  end

  defp initial_state(schema, state) when is_map(state) and not is_struct(state) do
    schema
    |> State.defaults_from_schema()
    |> State.merge(state)
    |> State.validate(schema)
  end

  defp initial_state(_schema, state) do
    invalid("Agent instance state must be a map", %{state: state})
  end

  defp known_keys(attrs) do
    case Map.keys(attrs) -- @definition_keys do
      [] -> :ok
      [key | _] -> invalid("Unknown Agent definition key", %{key: key})
    end
  end

  defp reject_instance_data(attrs) do
    keys =
      @instance_keys
      |> Enum.filter(&(Map.has_key?(attrs, &1) and not is_nil(Map.get(attrs, &1))))

    if keys == [] do
      :ok
    else
      invalid("Agent.new/1 accepts definition data only", %{keys: keys})
    end
  end

  defp instance_id(nil), do: {:ok, Jido.Util.generate_id()}
  defp instance_id(id), do: validate_id(id)

  defp validate_id(id) when is_binary(id) and byte_size(id) > 0, do: {:ok, id}
  defp validate_id(id), do: invalid("Agent id must be a non-empty string", %{id: id})

  @doc false
  def field(:name, name), do: Jido.Util.validate_name(name)

  def field(:description, description) when is_nil(description) or is_binary(description),
    do: {:ok, description}

  def field(:description, description) do
    invalid("Agent description must be a string or nil", %{description: description})
  end

  def field(:metadata, metadata) when is_map(metadata) and not is_struct(metadata),
    do: {:ok, metadata}

  def field(:metadata, metadata),
    do: invalid("Agent metadata must be a map", %{metadata: metadata})

  defp validate_module(module) when is_atom(module) and not is_nil(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        if function_exported?(module, :handle_signal, 2) do
          :ok
        else
          invalid("Agent module must implement handle_signal/2", %{module: module})
        end

      {:error, reason} ->
        invalid("Agent module could not be loaded", %{module: module, reason: reason})
    end
  end

  defp validate_module(module), do: invalid("Agent module must be a module", %{module: module})

  defp validate_routes(routes) when is_list(routes) do
    with {:ok, routes} <- Jido.Agent.Authoring.routes(routes),
         :ok <- validate_targets(routes) do
      {:ok, routes}
    else
      {:error, %_{} = error} -> {:error, error}
      {:error, reason} -> invalid("Invalid Agent routes", %{reason: reason})
    end
  end

  defp validate_routes(routes),
    do: invalid("Agent routes must be a list", %{routes: routes})

  defp validate_targets(routes) do
    Enum.reduce_while(routes, :ok, fn route, :ok ->
      {target, _defaults} = Authoring.split_target(route.target)

      case Jido.Executable.validate(target) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, invalid("Invalid Agent route executable", %{target: target, reason: reason})}
      end
    end)
  end

  defp normalize_attrs(attrs, source) do
    case Authoring.to_attrs(attrs) do
      {:ok, attrs} -> {:ok, attrs}
      :error -> invalid("Agent #{source} must be a map or keyword list", %{value: attrs})
    end
  end

  defp validate_instance_overrides(overrides) do
    case Map.keys(overrides) -- @instance_keys do
      [] -> :ok
      [key | _] -> invalid("Agent instances can set only :id and :state", %{key: key})
    end
  end

  defp invalid(message, details) do
    {:error, Error.validation_error(message, kind: :config, details: details)}
  end
end
