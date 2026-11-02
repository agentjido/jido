defmodule Jido.Signal.Router do
  @moduledoc """
  Maps Signal type patterns to ordered targets.

  A Router is an immutable indexed lookup value. It supports exact paths, the
  `*` single-segment wildcard, and the `**` multi-segment wildcard. It returns
  matching targets but does not execute them.

  Routes use this precedence:

  1. Exact paths
  2. Paths with `*`
  3. Paths with `**`
  4. Pattern complexity
  5. Higher explicit priority
  6. Earlier registration

  ## Examples

      alias Jido.Signal
      alias Jido.Signal.Router

      router =
        Router.new!([
          {"user.created", :create_user},
          {"user.*", :user_event},
          {"audit.**", :audit}
        ])

      {:ok, [:create_user, :user_event]} =
        Router.route(router, Signal.new!(type: "user.created", source: "/example"))

  A Route can also use a predicate. The predicate runs only after its path
  matches. Runtime routers accept a unary function. Compiled `use
  Jido.Signal.Router` modules accept only a `{module, function, args}` MFA:

      important? = fn signal -> signal.data[:important] == true end
      {:ok, router} = Router.add(router, {"job.completed", important?, :notify})
      {:ok, router} = Router.add(router, {"job.completed", {MyApp.Filter, :important?, []}, :notify})

  Router targets are generic terms. Dispatch target validation belongs to
  `Jido.Signal.Dispatch`.

  A route path may be a string pattern or a module defined with
  `use Jido.Signal`. A Signal module becomes its `type/0` value, which is
  always an exact path.

      defmodule MyApp.UserCreated do
        use Jido.Signal, type: "user.created", default_source: "/accounts"
      end

      {:ok, router} = Router.new({MyApp.UserCreated, :create_user})

  `use Jido.Signal.Router` compiles the same specifications into a module:

      defmodule MyApp.UserRouter do
        use Jido.Signal.Router

        route MyApp.UserCreated, :create_user
        route "user.*", :user_event
        route "audit.**", :audit, -50
        route "job.completed", {MyApp.Filter, :important?, []}, :notify
      end

      {:ok, [:create_user, :user_event]} = MyApp.UserRouter.route(signal)
  """

  alias Jido.Signal
  alias Jido.Signal.Error
  alias Jido.Signal.Router.Index

  @type path :: String.t() | module()
  @type match :: (Signal.t() -> boolean()) | {module(), atom(), list()}
  @type priority :: -100..100
  @type target :: term()

  @type route_spec ::
          {path(), target()}
          | {path(), target(), priority()}
          | {path(), match(), target()}
          | {path(), match(), target(), priority()}

  defmodule Router do
    @moduledoc false

    @empty_wildcard_index %{
      id: 0,
      exact: %{},
      single: nil,
      multi: nil,
      terminals: [],
      globstar?: false
    }

    @type t :: %__MODULE__{
            entries: [map()],
            exact_index: %{optional(String.t()) => [map()]},
            wildcard_index: map(),
            next_order: non_neg_integer(),
            next_node_id: pos_integer()
          }

    defstruct entries: [],
              exact_index: %{},
              wildcard_index: @empty_wildcard_index,
              next_order: 0,
              next_node_id: 1
  end

  alias __MODULE__.{Route, Router}

  @opaque t :: Router.t()
  @type new_opts :: keyword()

  @doc """
  Defines a Router module from `route` declarations.

  Each `route` uses the same specifications as `new/1`. Paths may be strings
  or `use Jido.Signal` modules. Match predicates in this compiled form must
  be `{module, function, args}` MFA values, not anonymous functions. The
  compiled module exposes `router/0`, `routes/0`, and `route/1`.
  """
  defmacro __using__(opts) do
    if opts != [] do
      raise ArgumentError, "use Jido.Signal.Router does not accept options"
    end

    quote do
      import Jido.Signal.Router.DSL, only: [route: 2, route: 3, route: 4]
      @before_compile Jido.Signal.Router.DSL
      Module.register_attribute(__MODULE__, :__jido_signal_routes__, accumulate: true)
    end
  end

  @doc """
  Resolves a route path.

  Accepts a path string or a module defined with `use Jido.Signal`. A Signal
  module becomes its `type/0` value. This does not create atoms.
  """
  @spec path(term()) :: {:ok, String.t()} | {:error, term()}
  def path(path) when is_binary(path), do: {:ok, path}

  def path(module) when is_atom(module) do
    if Signal.defined?(module) do
      signal_module_path(module, module.type())
    else
      invalid_path(module)
    end
  end

  def path(path), do: invalid_path(path)

  @doc """
  Normalizes and validates one or more route specifications.

  Accepted forms are `%Route{}`, `{path, target}`, `{path, target, priority}`,
  `{path, match, target}`, and `{path, match, target, priority}`. `path` may
  be a string or a `use Jido.Signal` module. `match` may be a unary function
  or a `{module, function, args}` MFA.
  """
  @spec normalize(Route.t() | [Route.t()] | route_spec() | [route_spec()]) ::
          {:ok, [Route.t()]} | {:error, term()}
  def normalize(%Route{} = route) do
    with {:ok, route} <- normalize_route_spec(route),
         {:ok, validated} <- validate(route) do
      {:ok, [validated]}
    end
  end

  def normalize(routes) when is_list(routes) and is_integer(length(routes)) do
    routes
    |> Enum.reduce_while({:ok, []}, fn input, {:ok, acc} ->
      with {:ok, route} <- normalize_route_spec(input),
           {:ok, route} <- validate(route) do
        {:cont, {:ok, [route | acc]}}
      else
        {:error, _error} = error -> {:halt, error}
      end
    end)
    |> reverse_normalized_routes()
  end

  def normalize(route_spec) when is_tuple(route_spec), do: normalize([route_spec])
  def normalize(invalid), do: invalid_route_spec(invalid)

  @doc "Creates a Router from route specifications."
  @spec new(route_spec() | [route_spec()] | [Route.t()] | nil, new_opts()) ::
          {:ok, t()} | {:error, term()}
  def new(routes \\ nil, opts \\ [])

  def new(nil, _opts), do: {:ok, %Router{}}

  def new(routes, _opts) do
    with {:ok, routes} <- normalize(routes) do
      {:ok, Index.new(routes)}
    end
  end

  @doc "Creates a Router and raises for an invalid route specification."
  @spec new!(route_spec() | [route_spec()] | [Route.t()] | nil, new_opts()) :: t()
  def new!(routes \\ nil, opts \\ []) do
    case new(routes, opts) do
      {:ok, router} ->
        router

      {:error, reason} ->
        raise Error.validation_error(
                "Invalid router configuration",
                %{field: "routes", value: routes, reason: reason}
              )
    end
  end

  @doc "Adds one or more routes and preserves their registration order."
  @spec add(t(), route_spec() | Route.t() | [route_spec()] | [Route.t()]) ::
          {:ok, t()} | {:error, term()}
  def add(%Router{} = router, routes) do
    with {:ok, routes} <- normalize(routes) do
      {:ok, Index.add(router, routes)}
    end
  end

  @doc "Removes all routes that have one of the specified paths."
  @spec remove(t(), path() | [path()]) :: {:ok, t()} | {:error, term()}
  def remove(%Router{} = router, paths) when is_list(paths) and is_integer(length(paths)) do
    with {:ok, paths} <- resolve_paths(paths) do
      {:ok, Index.remove(router, paths)}
    end
  end

  def remove(%Router{} = router, path) when is_binary(path) or is_atom(path),
    do: remove(router, [path])

  def remove(%Router{}, invalid), do: invalid_path(invalid)

  @doc "Appends routes or another Router to a Router."
  @spec merge(t(), t() | [Route.t()]) :: {:ok, t()} | {:error, term()}
  def merge(%Router{} = router, %Router{} = other) do
    with {:ok, routes} <- list(other), do: add(router, routes)
  end

  def merge(%Router{} = router, routes) when is_list(routes), do: add(router, routes)
  def merge(%Router{}, invalid), do: {:error, {:invalid_routes, invalid}}

  @doc "Lists Routes in registration order."
  @spec list(t()) :: {:ok, [Route.t()]}
  def list(%Router{} = router), do: {:ok, Enum.map(router.entries, & &1.route)}

  @doc "Returns the number of registered Route values."
  @spec count(t()) :: non_neg_integer()
  def count(%Router{entries: entries}), do: length(entries)

  @doc "Checks if a Router has no routes."
  @spec empty?(t()) :: boolean()
  def empty?(%Router{} = router), do: count(router) == 0

  @doc "Validates one or more Route values with the Route Zoi schema."
  @spec validate(Route.t() | [Route.t()]) ::
          {:ok, Route.t() | [Route.t()]} | {:error, term()}
  def validate(%Route{} = route) do
    case Zoi.parse(Route.schema(), route) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, route_validation_error(errors, route)}
    end
  end

  def validate(routes) when is_list(routes) and is_integer(length(routes)) do
    routes
    |> Enum.reduce_while({:ok, []}, fn
      %Route{} = route, {:ok, acc} ->
        case validate(route) do
          {:ok, validated} -> {:cont, {:ok, [validated | acc]}}
          {:error, _error} = error -> {:halt, error}
        end

      invalid, {:ok, _acc} ->
        {:halt,
         {:error,
          Error.validation_error("Expected Route struct", %{
            field: "route",
            value: invalid
          })}}
    end)
    |> case do
      {:ok, validated} -> {:ok, Enum.reverse(validated)}
      {:error, _error} = error -> error
    end
  end

  def validate(invalid) do
    {:error,
     Error.validation_error(
       "Expected Route struct or list of Route structs",
       %{field: "routes", value: invalid}
     )}
  end

  @doc """
  Returns all targets whose route path and optional `Route.match` predicate
  match a Signal.

  Returns the existing structured routing error when no target matches.
  """
  @spec route(t(), Signal.t()) :: {:ok, [term()]} | {:error, term()}
  def route(%Router{}, %Signal{type: nil}) do
    {:error,
     Error.routing_error(
       "Signal type cannot be nil",
       %{route: nil, reason: :nil_signal_type}
     )}
  end

  def route(%Router{} = router, %Signal{type: type} = signal) when is_binary(type) do
    targets = Index.lookup(router, type, signal)

    case targets do
      [] -> no_match(signal)
      targets -> {:ok, targets}
    end
  end

  def route(%Router{}, %Signal{} = signal) do
    {:error,
     Error.routing_error(
       "Signal type must be a string",
       %{route: signal.type, reason: :invalid_signal_type}
     )}
  end

  @doc "Checks if a Signal type matches a route path pattern."
  @spec matches?(String.t() | term(), String.t() | term()) :: boolean()
  def matches?(type, pattern) when is_binary(type) do
    case query_path(pattern) do
      {:ok, pattern} ->
        Index.matches?(type, pattern)

      {:error, _reason} ->
        false
    end
  end

  def matches?(_type, _pattern), do: false

  @doc "Filters Signals whose types match a route path pattern."
  @spec filter([Signal.t()] | term(), String.t() | term()) :: [Signal.t()]
  def filter(signals, pattern) when is_list(signals) and is_integer(length(signals)) do
    case query_path(pattern) do
      {:ok, pattern} ->
        Enum.filter(signals, fn
          %Signal{type: type} when is_binary(type) -> Index.matches?(type, pattern)
          _signal -> false
        end)

      {:error, _reason} ->
        []
    end
  end

  def filter(_signals, _pattern), do: []

  @doc "Checks if an exact route path is registered."
  @spec has_route?(t(), term()) :: boolean()
  def has_route?(%Router{} = router, path) do
    case query_path(path) do
      {:ok, path} ->
        Index.has_route?(router, path)

      {:error, _reason} ->
        false
    end
  end

  def has_route?(_router, _path), do: false

  defp query_path(input) do
    with {:ok, path} <- path(input),
         :ok <- Route.validate_path(path, []) do
      {:ok, path}
    end
  end

  defp normalize_route_spec(%Route{} = route) do
    case resolve_path(route.path) do
      {:ok, path} -> {:ok, %{route | path: path}}
      :invalid_path -> {:ok, route}
      {:error, _error} = error -> error
    end
  end

  defp normalize_route_spec({path, target} = spec) do
    bind_route(spec, resolve_path(path), fn path ->
      %Route{path: path, target: target}
    end)
  end

  defp normalize_route_spec({path, target, priority} = spec) when is_integer(priority) do
    bind_route(spec, resolve_path(path), fn path ->
      %Route{path: path, target: target, priority: priority}
    end)
  end

  defp normalize_route_spec({path, match, target} = spec) do
    if match_predicate?(match) do
      bind_route(spec, resolve_path(path), fn path ->
        %Route{path: path, match: match, target: target}
      end)
    else
      invalid_route_spec(spec)
    end
  end

  defp normalize_route_spec({path, match, target, priority} = spec) when is_integer(priority) do
    if match_predicate?(match) do
      bind_route(spec, resolve_path(path), fn path ->
        %Route{path: path, match: match, target: target, priority: priority}
      end)
    else
      invalid_route_spec(spec)
    end
  end

  defp normalize_route_spec(invalid), do: invalid_route_spec(invalid)

  defp match_predicate?(match) when is_function(match, 1), do: true

  defp match_predicate?({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args),
       do: true

  defp match_predicate?(_match), do: false

  defp bind_route(spec, resolved, fun) do
    case resolved do
      {:ok, path} -> {:ok, fun.(path)}
      :invalid_path -> invalid_route_spec(spec)
      {:error, _error} = error -> error
    end
  end

  defp resolve_path(path) do
    case path(path) do
      {:ok, path} ->
        {:ok, path}

      {:error, _error} = error ->
        if is_atom(path) and not Code.ensure_loaded?(path), do: :invalid_path, else: error
    end
  end

  defp resolve_paths(paths) do
    Enum.reduce_while(paths, {:ok, []}, fn input, {:ok, resolved} ->
      case path(input) do
        {:ok, path} -> {:cont, {:ok, [path | resolved]}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      {:error, _error} = error -> error
    end
  end

  defp signal_module_path(module, path) when is_binary(path) do
    if String.contains?(path, "*") do
      {:error,
       Error.validation_error("Signal module type must be an exact route path", %{
         field: "path",
         value: module,
         type: path
       })}
    else
      {:ok, path}
    end
  end

  defp signal_module_path(module, _path), do: invalid_path(module)

  defp invalid_path(path) do
    {:error,
     Error.validation_error("Expected a route path string or a Jido.Signal module", %{
       field: "path",
       value: path
     })}
  end

  defp invalid_route_spec(invalid) do
    {:error,
     Error.validation_error(
       "Invalid route specification format",
       %{
         value: invalid,
         expected_formats: [
           "%Route{}",
           "{path, target}",
           "{path, target, priority}",
           "{path, match, target}",
           "{path, match, target, priority}"
         ]
       }
     )}
  end

  defp reverse_normalized_routes({:ok, routes}), do: {:ok, Enum.reverse(routes)}
  defp reverse_normalized_routes({:error, _error} = error), do: error

  defp route_validation_error([%{message: message} | _errors], route) do
    Error.routing_error(message, %{route: route.path})
  end

  defp route_validation_error(_errors, route) do
    Error.routing_error("Invalid route", %{route: route.path})
  end

  defp no_match(signal) do
    {:error,
     Error.routing_error(
       "No matching handlers found for signal",
       %{signal_type: signal.type, route: signal.type, reason: :no_handlers_found}
     )}
  end
end
