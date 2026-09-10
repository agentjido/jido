defmodule Jido.Agent.Builder do
  @moduledoc """
  Builds an Agent definition in ordered steps through the canonical constructor.

  `build/1` returns a neutral definition. `build/2` also supplies instance
  options and returns a complete Agent. The Builder keeps its first error.
  Each added route is normalized and checked once, then stored in reverse
  order as in `Jido.Flow.Builder`. Build restores declaration order and
  validates the complete definition, including current executable contracts.

      builder =
        Jido.Agent.Builder.new(name: "counter")
        |> Jido.Agent.Builder.schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
        |> Jido.Agent.Builder.route("counter.add", MyApp.Add, defaults: %{amount: 1})

      {:ok, agent} = Jido.Agent.Builder.build(builder, id: "counter-1")
  """

  alias Jido.Agent
  alias Jido.Agent.Authoring

  @opaque t :: %__MODULE__{
            config: map(),
            reversed_routes: [Jido.Signal.Router.Route.t()],
            error: Exception.t() | nil
          }

  @enforce_keys [:config, :error]
  defstruct [:config, :error, reversed_routes: []]

  @doc "Starts a Builder with static Agent fields or an Agent module."
  @spec new(map() | keyword() | module()) :: t()
  def new(module) when is_atom(module) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         true <- function_exported?(module, :__agent_config__, 0),
         true <- function_exported?(module, :definition, 0),
         %Agent{id: nil, state: nil} = definition <- module.definition() do
      definition
      |> Map.from_struct()
      |> Map.drop([:id, :state])
      |> new()
    else
      _ -> failed("Expected an Agent module")
    end
  end

  def new(attrs) do
    with {:ok, attrs} <- Authoring.attrs(attrs),
         :ok <-
           Authoring.keys(attrs, [
             :module,
             :vsn,
             :name,
             :description,
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
  @spec name(t(), term()) :: t()
  def name(builder, value), do: put(builder, :name, value)
  @doc "Sets the Agent definition version."
  @spec vsn(t(), term()) :: t()
  def vsn(builder, value), do: put(builder, :vsn, value)
  @doc "Sets the description."
  @spec description(t(), term()) :: t()
  def description(builder, value), do: put(builder, :description, value)
  @doc "Sets the domain schema."
  @spec schema(t(), term()) :: t()
  def schema(builder, value), do: put(builder, :schema, value)
  @doc "Sets the metadata map."
  @spec metadata(t(), term()) :: t()
  def metadata(builder, value), do: put(builder, :metadata, value)

  @doc """
  Appends one route. Options are `:defaults`, `:priority`, and `:match`.
  Signal data overrides the defaults with a shallow merge during execution.
  """
  @spec route(t(), String.t(), term(), map() | keyword()) :: t()
  def route(builder, path, target, opts \\ [])

  def route(%__MODULE__{error: error} = builder, _path, _target, _opts) when not is_nil(error),
    do: builder

  def route(builder, path, target, opts) do
    with {:ok, route} <- Authoring.route(path, target, opts),
         :ok <- Authoring.validate_target(route.target) do
      %{builder | reversed_routes: [route | builder.reversed_routes]}
    else
      {:error, error} -> %{builder | error: error}
    end
  end

  @doc "Appends a Plugin with its keyword or map configuration."
  @spec plugin(t(), module(), keyword() | map()) :: t()
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
  @spec build(t()) :: {:ok, Agent.definition()} | {:error, Exception.t()}
  def build(%__MODULE__{error: error}) when not is_nil(error), do: {:error, error}

  def build(%__MODULE__{config: config, reversed_routes: routes}),
    do: Agent.new(Map.put(config, :routes, Enum.reverse(routes)))

  @doc "Builds a complete Agent with the supplied instance options."
  @spec build(t(), map() | keyword()) :: {:ok, Agent.instance()} | {:error, Exception.t()}
  def build(builder, opts) do
    with {:ok, definition} <- build(builder), do: Agent.instantiate(definition, opts)
  end

  @doc "Builds a definition or raises its error."
  @spec build!(t()) :: Agent.definition() | no_return()
  def build!(builder), do: unwrap!(build(builder))
  @doc "Builds an instance or raises its error."
  @spec build!(t(), map() | keyword()) :: Agent.instance() | no_return()
  def build!(builder, opts), do: unwrap!(build(builder, opts))

  defp put(%__MODULE__{error: error} = builder, _key, _value) when not is_nil(error), do: builder

  defp put(builder, :routes, value) do
    with {:ok, routes} <- Authoring.routes(value),
         {:ok, routes} <- Authoring.traverse(routes, &validate_route/1) do
      %{builder | reversed_routes: Enum.reverse(routes)}
    else
      {:error, error} -> %{builder | error: error}
    end
  end

  defp put(builder, key, value) do
    case valid_field(key, value) do
      :ok -> %{builder | config: Map.put(builder.config, key, value)}
      {:error, error} -> %{builder | error: error}
    end
  end

  defp valid_field(key, value) when key in [:name, :description, :metadata] do
    case Agent.Validation.field(key, value) do
      {:ok, _value} ->
        :ok

      {:error, _error} when key == :metadata ->
        Authoring.error("Agent metadata must be a plain map")

      {:error, error} when key == :description ->
        Authoring.error(error.message)

      error ->
        error
    end
  end

  defp valid_field(:schema, value), do: Agent.State.validate_schema(value)

  defp valid_field(:vsn, value), do: Agent.Validation.field(:vsn, value) |> status()

  defp valid_field(:plugins, value) do
    with {:ok, values} <- Authoring.traverse(value, &{:ok, &1}),
         {:ok, _} <- Jido.Plugin.canonical_declarations(values),
         do: :ok
  end

  defp valid_field(_key, _value), do: :ok

  defp status({:ok, _value}), do: :ok
  defp status({:error, _error} = error), do: error

  defp validate_route(route) do
    with :ok <- Authoring.validate_target(route.target), do: {:ok, route}
  end

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
