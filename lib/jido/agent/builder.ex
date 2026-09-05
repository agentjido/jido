defmodule Jido.Agent.Builder do
  @moduledoc """
  Builds an Agent definition in ordered steps through the canonical constructor.

  `build/1` returns a neutral definition. `build/2` also supplies instance
  options and returns a complete Agent. The Builder keeps its first error.

      builder =
        Jido.Agent.Builder.new(name: "counter")
        |> Jido.Agent.Builder.schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
        |> Jido.Agent.Builder.route("counter.add", MyApp.Add, defaults: %{amount: 1})

      {:ok, agent} = Jido.Agent.Builder.build(builder, id: "counter-1")
  """

  alias Jido.Agent
  alias Jido.Agent.Authoring

  @schema Zoi.struct(__MODULE__, %{
            config: Zoi.map(),
            error: Zoi.any() |> Zoi.nullable()
          })
  @opaque t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Builder schema."
  def schema, do: @schema

  @doc "Starts a Builder with static Agent fields or an Agent module."
  @spec new(map() | keyword() | module()) :: t()
  def new(module) when is_atom(module) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         true <- function_exported?(module, :__agent_config__, 0) do
      new(Map.put(module.__agent_config__(), :module, module))
    else
      _ -> failed("Expected an Agent module")
    end
  end

  def new(attrs) do
    with {:ok, attrs} <- Authoring.attrs(attrs),
         :ok <-
           Authoring.keys(attrs, [
             :module,
             :name,
             :description,
             :max_state_size,
             :schema,
             :metadata,
             :routes,
             :plugins
           ]) do
      builder = %__MODULE__{config: Map.take(attrs, [:module]), error: nil}

      Enum.reduce(Map.drop(attrs, [:module]), builder, fn {key, value}, acc ->
        put(acc, key, value)
      end)
    else
      {:error, error} -> %__MODULE__{config: %{}, error: error}
    end
  end

  @doc "Sets the name."
  def name(builder, value), do: put(builder, :name, value)
  @doc "Sets the description."
  def description(builder, value), do: put(builder, :description, value)
  @doc "Sets the complete state size limit in external term bytes."
  def max_state_size(builder, value), do: put(builder, :max_state_size, value)
  @doc "Sets the domain schema."
  def schema(builder, value), do: put(builder, :schema, value)
  @doc "Sets the metadata map."
  def metadata(builder, value), do: put(builder, :metadata, value)

  @doc """
  Appends one route. Options are `:defaults`, `:priority`, and `:match`.
  Signal data overrides the defaults with a shallow merge during execution.
  """
  def route(builder, path, target, opts \\ [])

  def route(%__MODULE__{error: error} = builder, _path, _target, _opts) when not is_nil(error),
    do: builder

  def route(builder, path, target, opts) do
    with {:ok, route} <- Authoring.route(path, target, opts),
         :ok <- validate_target(route.target) do
      append(builder, :routes, route)
    else
      {:error, error} -> %{builder | error: error}
    end
  end

  @doc "Appends a Plugin with its keyword or map configuration."
  def plugin(builder, module, config \\ [])

  def plugin(%__MODULE__{error: error} = builder, _module, _config) when not is_nil(error),
    do: builder

  def plugin(builder, module, config) do
    with {:ok, config} <- Authoring.options(config),
         {:ok, [plugin]} <- Jido.Plugin.canonical_declarations([{module, config}]) do
      append(builder, :plugins, plugin)
    else
      {:error, error} -> %{builder | error: error}
    end
  end

  @doc "Builds one neutral Agent definition."
  @spec build(t()) :: {:ok, Agent.t()} | {:error, Exception.t()}
  def build(%__MODULE__{error: error}) when not is_nil(error), do: {:error, error}
  def build(%__MODULE__{config: config}), do: Agent.new(config)

  @doc "Builds a complete Agent with the supplied instance options."
  @spec build(t(), map() | keyword()) :: {:ok, Agent.t()} | {:error, Exception.t()}
  def build(builder, opts) do
    with {:ok, definition} <- build(builder), do: Agent.instantiate(definition, opts)
  end

  @doc "Builds a definition or raises its error."
  def build!(builder), do: unwrap!(build(builder))
  @doc "Builds an instance or raises its error."
  def build!(builder, opts), do: unwrap!(build(builder, opts))

  defp put(%__MODULE__{error: error} = builder, _key, _value) when not is_nil(error), do: builder

  defp put(builder, key, value) do
    case valid_field(key, value) do
      :ok -> %{builder | config: Map.put(builder.config, key, value)}
      {:error, error} -> %{builder | error: error}
    end
  end

  defp valid_field(:name, value) do
    case Jido.Util.validate_name(value) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp valid_field(:max_state_size, value), do: Agent.StateBudget.validate_limit(value)

  defp valid_field(:schema, value), do: Agent.State.validate_schema(value)
  defp valid_field(:description, value) when is_nil(value) or is_binary(value), do: :ok

  defp valid_field(:description, _value),
    do: Authoring.error("Agent description must be a string or nil")

  defp valid_field(:metadata, value) when is_map(value) and not is_struct(value), do: :ok
  defp valid_field(:metadata, _value), do: Authoring.error("Agent metadata must be a plain map")

  defp valid_field(:routes, value) do
    with {:ok, routes} <- Authoring.routes(value),
         {:ok, _} <- Authoring.traverse(routes, &validate_route/1),
         do: :ok
  end

  defp valid_field(:plugins, value) do
    with {:ok, values} <- Authoring.traverse(value, &{:ok, &1}),
         {:ok, _} <- Jido.Plugin.canonical_declarations(values),
         do: :ok
  end

  defp valid_field(_key, _value), do: :ok

  defp validate_route(route) do
    with :ok <- validate_target(route.target), do: {:ok, route}
  end

  defp validate_target({target, defaults}) when is_map(defaults),
    do: Jido.Executable.validate(target)

  defp validate_target(target), do: Jido.Executable.validate(target)

  defp append(builder, key, value) do
    case Map.get(builder.config, key, []) do
      values when is_list(values) ->
        put(builder, key, values ++ [value])

      _ ->
        %{
          builder
          | error: elem(Authoring.error("Builder collection must be a list", %{key: key}), 1)
        }
    end
  end

  defp failed(message), do: %__MODULE__{config: %{}, error: elem(Authoring.error(message), 1)}
  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, error}), do: raise(error)
end
