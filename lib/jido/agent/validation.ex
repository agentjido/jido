defmodule Jido.Agent.Validation do
  @moduledoc false
  alias Jido.Agent.{Data, Error, Extension, Route, Topology}

  @fields [
    :id,
    :state,
    :module,
    :name,
    :description,
    :vsn,
    :schema,
    :metadata,
    :signal_source,
    :routes,
    :topology,
    :extensions
  ]

  def state_schema(%Jido.Agent{} = agent) do
    with {:ok, schema} <-
           Jido.Agent.Plugin.compose_schema(agent.schema, Jido.Agent.runtime_plugins(agent)),
         :ok <- Error.at(Data.schema(schema), :schema),
         do: {:ok, schema}
  end

  def define(input, opts \\ [])
  def define(%Jido.Agent{} = input, opts), do: define(Map.from_struct(input), opts)

  def define(input, opts) do
    related? = Keyword.get(opts, :related?, true)

    with {:ok, definition} <- Data.fields(input, @fields, Jido.Agent.__defaults__()),
         :ok <- fields(definition),
         {:ok, extensions} <- Error.at(Extension.normalize(definition.extensions), :extensions),
         {:ok, routes} <-
           Error.at(Data.list(definition.routes, &Route.normalize(&1, related?)), :routes),
         :ok <- Error.at(Data.unique(routes, & &1.path), :routes),
         :ok <- Error.at(Data.unique(Enum.reject(routes, &is_nil(&1.as)), & &1.as), :routes),
         definition = %{definition | routes: routes, extensions: extensions},
         {:ok, topology} <-
           Error.at(Topology.normalize(definition.topology, definition, opts), :topology),
         definition = %{definition | topology: topology},
         :ok <- verify_extensions(extensions, definition, related?),
         :ok <- plugin_schema(definition, related? and Keyword.get(opts, :plugin_schema?, true)) do
      {:ok, struct!(Jido.Agent, definition)}
    else
      {:error, %Error{} = error} ->
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

  defp verify_extensions(extensions, definition, true),
    do: Error.at(Extension.verify(extensions, definition), :extensions)

  defp verify_extensions(_, _, false), do: :ok

  defp plugin_schema(fields, true) do
    with {:ok, _schema} <- state_schema(struct!(Jido.Agent, fields)), do: :ok
  end

  defp plugin_schema(_, false), do: :ok

  def validate(%Jido.Agent{id: nil, state: nil} = value), do: validate_definition(value)
  def validate(%Jido.Agent{} = value), do: validate_instance(value)
  def validate(_), do: Error.fail(:invalid_agent, [], "Expected a Jido.Agent struct")

  def validate_definition(value, opts \\ [])

  def validate_definition(%Jido.Agent{} = value, opts) do
    with {:ok, normalized} <- define(value, opts) do
      if normalized === value,
        do: {:ok, value},
        else: Error.fail(:not_canonical, [], "Definition must contain its normalized fields")
    end
  end

  def validate_definition(_, _opts),
    do: Error.fail(:definition_required, [], "Expected a definition with nil id and state")

  def validate_instance(value) do
    with {:ok, agent, _specs, _schema} <- validate_instance_with_plugins(value), do: {:ok, agent}
  end

  def instantiate(source, opts) do
    with {:ok, definition} <- resolve(source),
         {:ok, opts} <- options(opts, [:id, :state]),
         :ok <- Error.at(Data.nonempty(opts[:id]), :id),
         {:ok, schema} <- Jido.Agent.Validation.state_schema(definition),
         {:ok, state} <- Error.at(Data.initialize(schema, Map.get(opts, :state, %{})), :state),
         {:ok, _} <- Topology.bind(definition, state),
         do: {:ok, %{definition | id: opts.id, state: state}}
  end

  def resolve(%Jido.Agent{} = definition), do: validate_definition(definition)

  def resolve(module) when is_atom(module) and module not in [nil, true, false] do
    if Code.ensure_loaded?(module) and function_exported?(module, :definition, 0),
      do: resolve_module(module),
      else:
        Error.fail(:unresolved_definition, [], "Agent definition module is not available", %{
          module: module
        })
  end

  def resolve(_),
    do: Error.fail(:definition_required, [], "Expected an Agent definition or module")

  defp resolve_module(module) do
    validate_definition(module.definition())
  rescue
    reason -> definition_failed(module, :error, reason)
  catch
    kind, reason -> definition_failed(module, kind, reason)
  end

  defp definition_failed(module, kind, reason),
    do:
      Error.fail(:definition_failed, [], "Agent module definition failed", %{
        module: module,
        kind: kind,
        reason: reason
      })

  def loaded_agent_module?(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :definition, 0)

  defp dependencies(agent) do
    with {:ok, specs} <- Jido.Plugin.Normalizer.normalize_all(Jido.Agent.runtime_plugins(agent)),
         {:ok, schema} <- Jido.Agent.Plugin.compose_schema_from_specs(agent.schema, specs),
         :ok <- Error.at(Data.schema(schema), :schema),
         do: {:ok, specs, schema}
  end

  def validate_instance_with_plugins(%Jido.Agent{} = value) do
    with :ok <- Error.at(Data.nonempty(value.id), :id),
         {:ok, definition} <-
           validate_definition(Jido.Agent.definition(value), plugin_schema?: false),
         {:ok, specs, schema} <- dependencies(definition),
         :ok <- Error.at(Data.complete(schema, value.state), :state),
         {:ok, _} <- Topology.bind(definition, value.state),
         do: {:ok, value, specs, schema}
  end

  def validate_instance_with_plugins(_),
    do: Error.fail(:instance_required, [], "Expected an Agent instance")

  def options(opts, allowed) when is_list(opts) do
    if Keyword.keyword?(opts) and
         length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))),
       do: Data.fields(Map.new(opts), allowed),
       else: Error.fail(:invalid_options, [], "Expected unique keyword options")
  end

  def options(opts, allowed), do: Data.fields(opts, allowed)

  defp fields(definition) do
    with :ok <- neutral(definition),
         :ok <- Error.at(Data.nonempty(definition[:name]), :name),
         :ok <- optional_module(definition.module),
         :ok <- optional_description(definition.description),
         :ok <- Error.at(Data.positive(definition.vsn), :vsn),
         :ok <- Error.at(Data.schema(definition.schema), :schema),
         :ok <- Error.at(Data.plain_map(definition.metadata), :metadata),
         :ok <- Error.at(Data.static(definition.metadata), :metadata),
         :ok <- source(definition.signal_source),
         do: :ok
  end

  defp neutral(%{id: nil, state: nil}), do: :ok
  defp neutral(_), do: Error.fail(:definition_required, [], "Definition id and state must be nil")
  defp optional_module(nil), do: :ok
  defp optional_module(module), do: Error.at(Data.name(module), :module)
  defp optional_description(nil), do: :ok
  defp optional_description(value) when is_binary(value), do: :ok

  defp optional_description(_),
    do: Error.fail(:invalid_description, :description, "Expected a description string or nil")

  defp source(nil), do: :ok
  defp source(value), do: Error.at(Data.nonempty(value), :signal_source)
end
