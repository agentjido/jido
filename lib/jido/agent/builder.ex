defmodule Jido.Agent.Builder do
  @moduledoc """
  Builds one inert canonical `Jido.Agent` definition from runtime data.

  `new/1` accepts an Agent name string as a short form. It also accepts a map
  or keyword list with the supported definition fields. Use the root setters
  and add functions to build a definition in steps.

      agent =
        Jido.Agent.Builder.new("support_agent")
        |> Jido.Agent.Builder.description("Handles support requests")
        |> Jido.Agent.Builder.plugin(MyApp.SupportPlugin, as: :support)
        |> Jido.Agent.Builder.route("support.requested", MyApp.HandleSupport)
        |> Jido.Agent.Builder.build!()

  The Builder creates definition data only. It does not create runtime
  identity, compile or instantiate an Agent, read host configuration, or start
  a process.
  """

  alias Jido.Agent
  alias Jido.Agent.Extension.Declaration, as: ExtensionDeclaration
  alias Jido.Agent.Plugin
  alias Jido.Agent.Schedule
  alias Jido.Error
  alias Jido.Signal.Router.Route

  @root_keys [:name, :description, :state_schema, :plugin_defaults, :metadata]
  @list_keys [:plugins, :routes, :schedules, :extensions]
  @runtime_keys [:id, :state, :agent_module]
  @supported_keys @root_keys ++ @list_keys

  @plugin_option_keys [:as, :config, :metadata]
  @route_option_keys [:match, :priority, :params]
  @schedule_option_keys [:timezone, :data, :metadata]
  @extension_option_keys [:data, :metadata]

  @opaque t :: %__MODULE__{
            config: map(),
            reversed_plugins: [Plugin.t()],
            reversed_routes: [Route.t()],
            reversed_schedules: [Schedule.t()],
            reversed_extensions: [ExtensionDeclaration.t()],
            error: Exception.t() | nil
          }

  @enforce_keys [
    :config,
    :reversed_plugins,
    :reversed_routes,
    :reversed_schedules,
    :reversed_extensions,
    :error
  ]
  defstruct @enforce_keys

  @doc """
  Starts a Builder from a name string or full definition data.

  Full definition data supports `:name`, `:description`, `:state_schema`,
  `:plugin_defaults`, `:metadata`, `:plugins`, `:routes`, `:schedules`, and
  `:extensions`. Runtime fields and strategy data are not Builder input.
  """
  @spec new(String.t() | map() | keyword()) :: t()
  def new(name) when is_binary(name), do: initialize(%{name: name})

  def new(attrs) when is_list(attrs) do
    case keyword_map(attrs, "Agent Builder root data") do
      {:ok, attrs} -> initialize(attrs)
      {:error, error} -> empty() |> fail(error)
    end
  end

  def new(%{} = attrs) when not is_struct(attrs), do: initialize(attrs)

  def new(_attrs),
    do: empty() |> fail(invalid("Agent Builder root data must be a map or keyword list"))

  @doc "Sets the optional Agent description."
  @spec description(t(), String.t() | nil) :: t()
  def description(%__MODULE__{} = builder, value),
    do: put_root(builder, :description, value)

  @doc "Sets the static Agent state schema."
  @spec state_schema(t(), Jido.Action.schema()) :: t()
  def state_schema(%__MODULE__{} = builder, value),
    do: put_root(builder, :state_schema, value)

  @doc "Sets the canonical default-plugin policy."
  @spec plugin_defaults(t(), term()) :: t()
  def plugin_defaults(%__MODULE__{} = builder, value),
    do: put_root(builder, :plugin_defaults, value)

  @doc "Sets portable author metadata."
  @spec metadata(t(), map()) :: t()
  def metadata(%__MODULE__{} = builder, value),
    do: put_root(builder, :metadata, value)

  @doc """
  Adds one canonical plugin declaration.

  The declaration can be a plugin module, a `Jido.Agent.Plugin`, a map, or a
  keyword list. Module input also accepts `:as`, `:config`, and `:metadata`
  options.
  """
  @spec plugin(t(), module() | Plugin.t() | map() | keyword(), keyword()) :: t()
  def plugin(builder, declaration, opts \\ [])

  def plugin(%__MODULE__{} = builder, declaration, opts) do
    result =
      with {:ok, opts} <- options(opts, @plugin_option_keys),
           {:ok, input} <- declaration_input(declaration, opts, :module) do
        Plugin.new(input)
      end

    add_result(builder, :reversed_plugins, result)
  end

  @doc """
  Adds one canonical route.

  It accepts a canonical `Jido.Signal.Router.Route`, an Agent route tuple, or a
  map or keyword list with `:path`, `:target`, `:match`, `:priority`, and
  `:params`. The path and target form accepts `:match`, `:priority`, and
  `:params` options.
  """
  @spec route(t(), Route.t() | tuple() | map() | keyword()) :: t()
  def route(%__MODULE__{} = builder, route), do: add_route(builder, route, [])

  @spec route(t(), String.t(), term()) :: t()
  def route(%__MODULE__{} = builder, path, target) when is_binary(path),
    do: add_route(builder, %{path: path, target: target}, [])

  @spec route(t(), Route.t() | tuple() | map() | keyword(), keyword()) :: t()
  def route(%__MODULE__{} = builder, route, opts), do: add_route(builder, route, opts)

  @spec route(t(), String.t(), term(), keyword()) :: t()
  def route(%__MODULE__{} = builder, path, target, opts),
    do: add_route(builder, %{path: path, target: target}, opts)

  @doc """
  Adds one canonical schedule declaration.

  It accepts a `Jido.Agent.Schedule`, a map, or a keyword list. The practical
  form takes a name, cron expression, signal type, and optional `:timezone`,
  `:data`, and `:metadata` options.
  """
  @spec schedule(t(), Schedule.t() | map() | keyword()) :: t()
  def schedule(%__MODULE__{} = builder, declaration),
    do: add_schedule(builder, declaration, [])

  @spec schedule(t(), Schedule.t() | map() | keyword(), keyword()) :: t()
  def schedule(%__MODULE__{} = builder, declaration, opts),
    do: add_schedule(builder, declaration, opts)

  @spec schedule(t(), String.t(), String.t(), String.t(), keyword()) :: t()
  def schedule(builder, name, cron_expression, signal_type, opts \\ [])

  def schedule(%__MODULE__{} = builder, name, cron_expression, signal_type, opts) do
    declaration = %{
      name: name,
      cron_expression: cron_expression,
      signal_type: signal_type
    }

    add_schedule(builder, declaration, opts)
  end

  @doc """
  Adds one canonical extension declaration.

  It accepts an extension module, a `Jido.Agent.Extension.Declaration`, a map,
  or a keyword list. The module and data form accepts a `:metadata` option.
  """
  @spec extension(t(), module() | ExtensionDeclaration.t() | map() | keyword()) :: t()
  def extension(%__MODULE__{} = builder, declaration),
    do: add_extension(builder, declaration, [])

  @spec extension(t(), module(), term()) :: t()
  def extension(%__MODULE__{} = builder, module, value) when is_atom(module) do
    if keyword_options?(value) do
      add_extension(builder, module, value)
    else
      add_extension(builder, %{module: module, data: value}, [])
    end
  end

  @spec extension(t(), ExtensionDeclaration.t() | map() | keyword(), keyword()) :: t()
  def extension(%__MODULE__{} = builder, declaration, opts),
    do: add_extension(builder, declaration, opts)

  @spec extension(t(), module(), term(), keyword()) :: t()
  def extension(%__MODULE__{} = builder, module, data, opts),
    do: add_extension(builder, %{module: module, data: data}, opts)

  @doc "Builds and validates the canonical Agent definition."
  @spec build(t()) :: {:ok, Agent.t()} | {:error, Exception.t()}
  def build(%__MODULE__{error: %_{} = error}), do: {:error, error}

  def build(%__MODULE__{} = builder) do
    builder.config
    |> Map.put(:plugins, Enum.reverse(builder.reversed_plugins))
    |> Map.put(:routes, Enum.reverse(builder.reversed_routes))
    |> Map.put(:schedules, Enum.reverse(builder.reversed_schedules))
    |> Map.put(:extensions, Enum.reverse(builder.reversed_extensions))
    |> Agent.new()
  end

  @doc "Builds the canonical Agent definition or raises its validation error."
  @spec build!(t()) :: Agent.t() | no_return()
  def build!(%__MODULE__{} = builder) do
    case build(builder) do
      {:ok, agent} -> agent
      {:error, error} -> raise error
    end
  end

  defp initialize(attrs) do
    with :ok <- known_root_keys(attrs),
         {:ok, root} <- canonical_root(Map.take(attrs, @root_keys)) do
      root
      |> builder_from_root()
      |> add_all(:plugins, Map.get(attrs, :plugins, []))
      |> add_all(:routes, Map.get(attrs, :routes, []))
      |> add_all(:schedules, Map.get(attrs, :schedules, []))
      |> add_all(:extensions, Map.get(attrs, :extensions, []))
    else
      {:error, error} -> empty() |> fail(error)
    end
  end

  defp known_root_keys(attrs) do
    keys = Map.keys(attrs)

    case Enum.find(@runtime_keys, &Enum.member?(keys, &1)) do
      nil ->
        case Enum.find(keys, &(&1 not in @supported_keys)) do
          nil ->
            :ok

          key ->
            {:error, invalid("unknown Agent Builder root field: #{inspect(key)}", %{key: key})}
        end

      key ->
        {:error,
         invalid("Agent Builder does not accept runtime fields", %{
           field: key,
           fields: @runtime_keys
         })}
    end
  end

  defp canonical_root(attrs) do
    case Agent.new(attrs) do
      {:ok, agent} -> {:ok, Map.take(Map.from_struct(agent), @root_keys)}
      {:error, error} -> {:error, error}
    end
  end

  defp builder_from_root(config) do
    %__MODULE__{
      config: config,
      reversed_plugins: [],
      reversed_routes: [],
      reversed_schedules: [],
      reversed_extensions: [],
      error: nil
    }
  end

  defp empty do
    %__MODULE__{
      config: %{},
      reversed_plugins: [],
      reversed_routes: [],
      reversed_schedules: [],
      reversed_extensions: [],
      error: nil
    }
  end

  defp add_all(builder, field, values) when is_list(values) do
    if List.improper?(values) do
      fail(builder, invalid("Agent Builder #{field} must be a proper list", %{field: field}))
    else
      Enum.reduce(values, builder, fn value, builder -> add_one(builder, field, value) end)
    end
  end

  defp add_all(builder, field, _values),
    do: fail(builder, invalid("Agent Builder #{field} must be a list", %{field: field}))

  defp add_one(builder, :plugins, value), do: plugin(builder, value)
  defp add_one(builder, :routes, value), do: route(builder, value)
  defp add_one(builder, :schedules, value), do: schedule(builder, value)
  defp add_one(builder, :extensions, value), do: extension(builder, value)

  defp put_root(builder, field, value) do
    case canonical_root(Map.put(builder.config, field, value)) do
      {:ok, config} -> put_config(builder, config)
      {:error, error} -> fail(builder, error)
    end
  end

  defp put_config(%__MODULE__{error: nil} = builder, config), do: %{builder | config: config}
  defp put_config(builder, _config), do: builder

  defp add_route(builder, route, opts) do
    result =
      with {:ok, opts} <- options(opts, @route_option_keys),
           {:ok, attrs} <- route_attrs(route),
           {:ok, attrs} <- merge_fields(attrs, opts),
           {:ok, route_spec} <- route_spec(attrs) do
        canonical_route(route_spec)
      end

    add_result(builder, :reversed_routes, result)
  end

  defp canonical_route(route_spec) do
    case Agent.new(name: "agent_builder_route", routes: [route_spec]) do
      {:ok, %Agent{routes: [route]}} -> {:ok, route}
      {:error, error} -> {:error, error}
    end
  end

  defp route_attrs(%Route{} = route), do: {:ok, Map.from_struct(route)}

  defp route_attrs(route) when is_list(route),
    do: keyword_map(route, "Agent Builder route")

  defp route_attrs(%{} = route) when not is_struct(route), do: {:ok, route}
  defp route_attrs({path, target}), do: {:ok, %{path: path, target: target}}

  defp route_attrs({path, target, params}) when is_atom(target) and is_map(params),
    do: {:ok, %{path: path, target: target, params: params}}

  defp route_attrs({path, match, target}) when is_function(match, 1),
    do: {:ok, %{path: path, match: match, target: target}}

  defp route_attrs({path, target, priority}),
    do: {:ok, %{path: path, target: target, priority: priority}}

  defp route_attrs({path, target, params, priority})
       when is_atom(target) and is_map(params),
       do: {:ok, %{path: path, target: target, params: params, priority: priority}}

  defp route_attrs({path, match, target, params})
       when is_function(match, 1) and is_atom(target) and is_map(params),
       do: {:ok, %{path: path, match: match, target: target, params: params}}

  defp route_attrs({path, match, target, priority}),
    do: {:ok, %{path: path, match: match, target: target, priority: priority}}

  defp route_attrs({path, match, target, params, priority}),
    do: {:ok, %{path: path, match: match, target: target, params: params, priority: priority}}

  defp route_attrs(value),
    do:
      {:error,
       invalid("Agent Builder route must be a canonical route, tuple, map, or keyword list", %{
         value: value
       })}

  defp route_spec(attrs) do
    with :ok <- known_fields(attrs, [:path, :target | @route_option_keys], "route"),
         {:ok, target} <- route_target(attrs) do
      path = Map.get(attrs, :path)
      match = Map.get(attrs, :match)
      priority = Map.get(attrs, :priority)

      case {match, priority} do
        {nil, nil} -> {:ok, {path, target}}
        {nil, priority} -> {:ok, {path, target, priority}}
        {match, nil} -> {:ok, {path, match, target}}
        {match, priority} -> {:ok, {path, match, target, priority}}
      end
    end
  end

  defp route_target(attrs) do
    target = Map.get(attrs, :target)

    case Map.fetch(attrs, :params) do
      {:ok, params} ->
        if match?({_, %{}}, target) do
          {:error, invalid("Agent Builder route contains duplicate static parameters")}
        else
          {:ok, {target, params}}
        end

      :error ->
        {:ok, target}
    end
  end

  defp add_schedule(builder, declaration, opts) do
    result =
      with {:ok, opts} <- options(opts, @schedule_option_keys),
           {:ok, input} <- declaration_input(declaration, opts) do
        Schedule.new(input)
      end

    add_result(builder, :reversed_schedules, result)
  end

  defp add_extension(builder, declaration, opts) do
    result =
      with {:ok, opts} <- options(opts, @extension_option_keys),
           {:ok, input} <- declaration_input(declaration, opts, :module) do
        ExtensionDeclaration.new(input)
      end

    add_result(builder, :reversed_extensions, result)
  end

  defp declaration_input(declaration, opts, shorthand_key \\ nil)

  defp declaration_input(declaration, opts, shorthand_key)
       when is_atom(declaration) and not is_nil(shorthand_key) do
    merge_fields(%{shorthand_key => declaration}, opts)
  end

  defp declaration_input(%_{} = declaration, opts, _shorthand_key),
    do: declaration |> Map.from_struct() |> merge_fields(opts)

  defp declaration_input(declaration, opts, _shorthand_key) when is_map(declaration),
    do: merge_fields(declaration, opts)

  defp declaration_input(declaration, opts, _shorthand_key) when is_list(declaration) do
    with {:ok, declaration} <- keyword_map(declaration, "Agent Builder declaration") do
      merge_fields(declaration, opts)
    end
  end

  defp declaration_input(declaration, opts, _shorthand_key) when map_size(opts) == 0,
    do: {:ok, declaration}

  defp declaration_input(_declaration, _opts, _shorthand_key),
    do: {:error, invalid("Agent Builder options require map or keyword declaration data")}

  defp options(opts, allowed) when is_list(opts) do
    with {:ok, opts} <- keyword_map(opts, "Agent Builder options"),
         :ok <- known_fields(opts, allowed, "options") do
      {:ok, opts}
    end
  end

  defp options(_opts, _allowed),
    do: {:error, invalid("Agent Builder options must be a keyword list")}

  defp keyword_map(value, label) do
    if Keyword.keyword?(value) do
      keys = Keyword.keys(value)

      if Enum.uniq(keys) == keys do
        {:ok, Map.new(value)}
      else
        {:error, invalid("#{label} must not contain duplicate fields")}
      end
    else
      {:error, invalid("#{label} must be a keyword list")}
    end
  end

  defp known_fields(attrs, allowed, label) do
    fields = attrs |> Map.keys() |> Enum.reject(&Enum.member?(allowed, &1)) |> Enum.sort()

    case fields do
      [] ->
        :ok

      fields ->
        {:error, invalid("Agent Builder #{label} contain unsupported fields", %{fields: fields})}
    end
  end

  defp merge_fields(attrs, additions) do
    duplicates = attrs |> Map.keys() |> Enum.filter(&Map.has_key?(additions, &1)) |> Enum.sort()

    case duplicates do
      [] ->
        {:ok, Map.merge(attrs, additions)}

      fields ->
        {:error, invalid("Agent Builder input contains duplicate fields", %{fields: fields})}
    end
  end

  defp keyword_options?(value) when is_list(value), do: Keyword.keyword?(value)
  defp keyword_options?(_value), do: false

  defp add_result(builder, field, {:ok, value}), do: append(builder, field, value)
  defp add_result(builder, _field, {:error, error}), do: fail(builder, error)

  defp append(%__MODULE__{error: nil} = builder, field, value),
    do: Map.update!(builder, field, &[value | &1])

  defp append(builder, _field, _value), do: builder

  defp fail(%__MODULE__{error: nil} = builder, error),
    do: %{builder | error: normalize_error(error)}

  defp fail(builder, _error), do: builder

  defp normalize_error(error) when is_exception(error), do: error

  defp normalize_error(reason),
    do: invalid("Agent Builder could not normalize declaration data", %{reason: reason})

  defp invalid(message, details \\ %{}),
    do: Error.validation_error(message, details: details)
end
