defmodule Jido.Signal.Router do
  @moduledoc """
  The Router module implements a high-performance, trie-based signal routing system designed specifically for agent-based architectures. It provides sophisticated message routing capabilities with support for exact matches, wildcards, pattern matching functions, and multiple dispatch targets.

  ## Core Concepts

  The Router organizes signal handlers into an efficient trie (prefix tree) structure that enables:
  - Fast path-based routing using dot-notation (e.g., "user.created.verified")
  - Priority-based handler execution (-100 to 100)
  - Complexity-based ordering for wildcard resolution
  - Dynamic route management (add/remove at runtime)
  - Pattern matching through custom functions
  - Multiple dispatch targets per route

  ### Path Patterns

  Routes use a dot-notation pattern system supporting:
  - Exact matches: `"user.created"`
  - Single wildcards: `"user.*.updated"` (matches one segment)
  - Multi-level wildcards: `"audit.**"` (matches zero or more segments)

  Pattern rules:
  - Paths must match: `^[a-zA-Z0-9.*_-]+(\.[a-zA-Z0-9.*_-]+)*$`
  - Cannot contain consecutive dots (..)
  - Cannot contain consecutive multi-wildcards (`**...**`)

  ### Handler Priority

  Handlers execute in order based on:
  1. Path complexity (more specific paths execute first)
  2. Priority (-100 to 100, higher executes first)
  3. Registration order (for equal priority/complexity)

  ### Dispatch Configurations

  The router supports two types of targets:
  1. Instructions - Standard action instructions with parameters
  2. Dispatch Configs - Adapter-based dispatch configurations

  Dispatch configs can be specified in two formats:
  1. Single adapter: `{adapter, opts}`
  2. Multiple adapters: `[{adapter1, opts1}, {adapter2, opts2}]`

  ## Usage Examples

  Basic route creation:
  ```elixir
  {:ok, router} = Router.new([
    # Simple route with default priority
    {"user.created", %Instruction{action: HandleUserCreated}},

    # High-priority audit logging
    {"audit.**", %Instruction{action: AuditLogger}, 100},

    # Pattern matching for large payments
    {"payment.processed",
      fn signal -> signal.data.amount > 1000 end,
      %Instruction{action: HandleLargePayment}},

    # Single dispatch target
    {"metrics.collected", {MetricsAdapter, [type: :counter]}},

    # Multiple dispatch targets
    {"system.error", [
      {MetricsAdapter, [type: :error]},
      {AlertAdapter, [priority: :high]},
      {LogAdapter, [level: :error]}
    ]}
  ])
  ```

  Dynamic route management:
  ```elixir
  # Add routes
  {:ok, router} = Router.add(router, [
    {"metrics.**", {MetricsAdapter, [type: :gauge]}}
  ])

  # Remove routes
  {:ok, router} = Router.remove(router, "metrics.**")
  ```

  Signal routing:
  ```elixir
  # Route to instruction
  {:ok, [%Instruction{action: HandleUserCreated}]} = Router.route(router, %Signal{
    type: "user.created",
    data: %{id: "123"}
  })

  # Route to multiple dispatch targets
  {:ok, [
    {MetricsAdapter, [type: :error]},
    {AlertAdapter, [priority: :high]},
    {LogAdapter, [level: :error]}
  ]} = Router.route(router, %Signal{
    type: "system.error",
    data: %{message: "Critical error"}
  })
  ```

  ## Path Complexity Scoring

  The router uses a sophisticated scoring system to determine handler execution order:

  1. Base score from segment count (length * 2000)
  2. Exact match bonuses (3000 per segment, weighted by position)
  3. Wildcard penalties:
     - Single wildcard (*): 1000 - position_index * 100
     - Multi-wildcard (**): 2000 - position_index * 200

  This ensures more specific routes take precedence over wildcards, while maintaining predictable execution order.

  ## Best Practices

  1. Route Design
     - Use consistent, hierarchical path patterns
     - Prefer exact matches over wildcards when possible
     - Keep path segments meaningful and well-structured
     - Document your path hierarchy

  2. Priority Management
     - Reserve high priorities (75-100) for critical handlers
     - Use default priority (0) for standard business logic
     - Reserve low priorities (-100 to -75) for metrics/logging
     - Document priority ranges for your application

  3. Pattern Matching
     - Keep match functions simple and fast
     - Handle nil/missing data gracefully
     - Avoid side effects in match functions
     - Test edge cases thoroughly

  4. Dispatch Configuration
     - Use single dispatch for simple routing
     - Use multiple dispatch for cross-cutting concerns
     - Keep adapter options minimal and focused
     - Document adapter requirements

  5. Performance Considerations
     - Monitor route count in production
     - Use pattern matching sparingly
     - Consider complexity scores when designing paths
     - Profile routing performance under load

  ## Error Handling

  The router provides detailed error feedback for:
  - Invalid path patterns
  - Priority out of bounds
  - Invalid match functions
  - Missing handlers
  - Malformed signals
  - Invalid dispatch configurations

  ## Implementation Details

  The router uses several specialized structs:
  - `Route` - Defines a single routing rule
  - `TrieNode` - Internal trie structure node
  - `HandlerInfo` - Stores handler metadata
  - `PatternMatch` - Encapsulates pattern matching rules

  See the corresponding typespecs for detailed field information.

  ## See Also

  - `Jido.Signal` - Signal structure and validation
  - `Jido.Instruction` - Handler instruction format
  - `Jido.Error` - Error types and handling
  - `Jido.Signal.Dispatch` - Dispatch adapter interface
  """
  use Private
  use TypedStruct

  alias Jido.Signal
  alias Jido.Error
  alias Jido.Signal.Router.{Engine, Route, Validator}

  @type path :: String.t()
  @type match :: (Signal.t() -> boolean())
  @type priority :: non_neg_integer()
  @type wildcard_type :: :single | :multi
  @type target :: term()

  @type route_spec ::
          {String.t(), target()}
          | {String.t(), target(), priority()}
          | {String.t(), match(), target()}
          | {String.t(), match(), target(), priority()}

  @doc """
  Normalizes route specifications into Route structs.

  ## Parameters
  * `input` - One of:
    * Single Route struct
    * List of Route structs
    * List of route_spec tuples:
      * {path, target} tuple where target can be any term
      * {path, target, priority} tuple
      * {path, match_fn, target} tuple
      * {path, match_fn, target, priority} tuple
  ## Returns
    * `{:ok, [%Route{}]}` - List of normalized Route structs
    * `{:error, term()}` - If normalization fails
  """
  @spec normalize(Route.t() | [Route.t()] | route_spec() | [route_spec()]) ::
          {:ok, [Route.t()]} | {:error, term()}
  defdelegate normalize(input), to: Validator

  typedstruct module: HandlerInfo do
    @moduledoc "Router Helper struct to store handler metadata"
    @default_priority 0
    field(:target, Jido.Signal.Router.target(), enforce: true)
    field(:priority, Jido.Signal.Router.priority(), default: @default_priority)
    field(:complexity, non_neg_integer(), default: 0)
  end

  typedstruct module: PatternMatch do
    @moduledoc "Router Helper struct to store pattern match metadata"
    @default_priority 0
    field(:match, Jido.Signal.Router.match(), enforce: true)
    field(:target, Jido.Signal.Router.target(), enforce: true)
    field(:priority, Jido.Signal.Router.priority(), default: @default_priority)
    field(:complexity, non_neg_integer(), default: 0)
  end

  typedstruct module: NodeHandlers do
    @moduledoc "Router Helper struct to store node handler metadata"
    field(:handlers, [HandlerInfo.t()], default: [])
    field(:matchers, [PatternMatch.t()], default: [])
  end

  typedstruct module: WildcardHandlers do
    @moduledoc "Router Helper struct to store wildcard handler metadata"
    field(:type, Jido.Signal.Router.wildcard_type(), enforce: true)
    field(:handlers, NodeHandlers.t(), enforce: true)
  end

  typedstruct module: TrieNode do
    @moduledoc "Router Helper struct to store trie node metadata"
    field(:segments, %{String.t() => TrieNode.t()}, default: %{})
    field(:wildcards, [WildcardHandlers.t()], default: [])
    field(:handlers, NodeHandlers.t())
  end

  typedstruct module: Route do
    @moduledoc "Router Helper struct to store route metadata"
    @default_priority 0
    field(:path, Jido.Signal.Router.path(), enforce: true)
    field(:target, Jido.Signal.Router.target(), enforce: true)
    field(:priority, Jido.Signal.Router.priority(), default: @default_priority)
    field(:match, Jido.Signal.Router.match())
  end

  typedstruct module: Router do
    @moduledoc "Router Helper struct to store router metadata"
    field(:trie, TrieNode.t(), default: %TrieNode{})
    field(:route_count, non_neg_integer(), default: 0)
  end

  @doc """
  Creates a new router with the given routes.
  """
  @spec new(route_spec() | [route_spec()] | [Route.t()] | nil) ::
          {:ok, Router.t()} | {:error, term()}
  def new(routes \\ nil)

  def new(nil), do: {:ok, %Router{}}

  def new(routes) do
    with {:ok, normalized} <- Validator.normalize(routes),
         {:ok, validated} <- validate(normalized) do
      trie = Engine.build_trie(validated)
      {:ok, %Router{trie: trie, route_count: length(validated)}}
    end
  end

  @doc """
  Creates a new router with the given routes, raising on error.
  """
  @spec new!(route_spec() | [route_spec()] | [Route.t()] | nil) :: Router.t()
  def new!(routes \\ nil) do
    case new(routes) do
      {:ok, router} ->
        router

      {:error, reason} ->
        {:error,
         Error.validation_error("Invalid router configuration", %{
           reason: reason
         })}
    end
  end

  @doc """
  Adds one or more routes to the router.

  ## Parameters
  - router: The existing router struct
  - routes: A route specification or list of route specifications in one of these formats:
    - %Route{}
    - {path, instruction}
    - {path, instruction, priority}
    - {path, [match: match_fn], instruction}
    - {path, [match: match_fn], instruction, priority}

  ## Returns
  `{:ok, updated_router}` or `{:error, reason}`
  """
  @spec add(Router.t(), route_spec() | Route.t() | [route_spec()] | [Route.t()]) ::
          {:ok, Router.t()} | {:error, term()}
  def add(%Router{} = router, routes) when is_list(routes) do
    with {:ok, normalized} <- Validator.normalize(routes),
         {:ok, validated} <- validate(normalized) do
      new_trie = Engine.build_trie(validated, router.trie)
      {:ok, %Router{router | trie: new_trie, route_count: router.route_count + length(validated)}}
    end
  end

  def add(%Router{} = router, route) do
    add(router, [route])
  end

  @doc """
  Removes one or more routes from the router.

  ## Parameters
  - router: The Router struct to modify
  - paths: A path string or list of path strings to remove

  ## Returns
  - `{:ok, updated_router}` - Routes removed successfully

  ## Examples

      {:ok, router} = Router.remove(router, "metrics.collected")
      {:ok, router} = Router.remove(router, ["user.created", "user.updated"])
  """
  @spec remove(Router.t(), String.t() | [String.t()]) :: {:ok, Router.t()}
  def remove(%Router{} = router, paths) when is_list(paths) do
    new_trie = Enum.reduce(paths, router.trie, &Engine.remove_path/2)
    route_count = Engine.count_routes(new_trie)
    {:ok, %Router{router | trie: new_trie, route_count: route_count}}
  end

  def remove(%Router{} = router, path) when is_binary(path) do
    remove(router, [path])
  end

  @doc """
  Merges two routers by combining their routes.

  Takes a target router and a list of routes from another router (obtained via `list/1`) and
  merges them together, preserving priorities and match functions.

  ## Parameters
  - router: The target Router struct to merge into
  - routes: List of Route structs to merge in (from Router.list/1)

  ## Returns
  `{:ok, merged_router}` or `{:error, reason}`

  ## Examples

      {:ok, router1} = Router.new([{"user.created", instruction1}])
      {:ok, router2} = Router.new([{"payment.processed", instruction2}])
      {:ok, routes2} = Router.list(router2)

      # Merge router2's routes into router1
      {:ok, merged} = Router.merge(router1, routes2)
  """
  @spec merge(Router.t(), [Route.t()]) :: {:ok, Router.t()} | {:error, term()}
  def merge(%Router{} = router, routes) when is_list(routes) do
    # Convert Route structs back to route specs for add/2
    route_specs =
      Enum.map(routes, fn route ->
        case route.match do
          nil ->
            {route.path, route.target, route.priority}

          match_fn when is_function(match_fn) ->
            {route.path, match_fn, route.target, route.priority}
        end
      end)

    add(router, route_specs)
  end

  def merge(%Router{} = router, %Router{} = other) do
    with {:ok, routes} <- list(other) do
      merge(router, routes)
    end
  end

  def merge(%Router{} = _router, invalid) do
    {:error, {:invalid_routes, invalid}}
  end

  @doc """
  Lists all routes currently registered in the router.

  Returns a list of Route structs containing the path, target, priority and match function
  for each registered route.

  ## Returns
  `{:ok, [%Route{}]}` - List of Route structs

  ## Examples

      {:ok, routes} = Router.list(router)

      # Returns:
      [
        %Route{
          path: "user.created",
          target: MyApp.Actions.HandleUserCreated,
          priority: 0,
          match: nil
        },
        %Route{
          path: "payment.processed",
          target: {:some_adapter, [opts: :here]},
          priority: 90,
          match: #Function<1.123456789/1>
        }
      ]
  """
  @spec list(Router.t()) :: {:ok, [Route.t()]}
  def list(%Router{} = router) do
    routes = Engine.collect_routes(router.trie)
    {:ok, routes}
  end

  @doc """
  Validates one or more Route structs.

  ## Parameters
  - routes: A %Route{} struct or list of %Route{} structs to validate

  ## Returns

  * `{:ok, %Route{}}` - Single validated Route struct
  * `{:ok, [%Route{}]}` - List of validated Route structs
  * `{:error, term()}` - If validation fails
  """
  @spec validate(Route.t() | [Route.t()]) :: {:ok, Route.t() | [Route.t()]} | {:error, term()}
  def validate(%Route{} = route) do
    with {:ok, path} <- Validator.validate_path(route.path),
         {:ok, target} <- Validator.validate_target(route.target),
         {:ok, match} <- Validator.validate_match(route.match),
         {:ok, priority} <- Validator.validate_priority(route.priority) do
      {:ok,
       %Route{
         path: path,
         target: target,
         match: match,
         priority: priority
       }}
    end
  end

  def validate(routes) when is_list(routes) do
    routes
    |> Enum.reduce_while({:ok, []}, fn
      %Route{} = route, {:ok, acc} ->
        case validate(route) do
          {:ok, validated} -> {:cont, {:ok, [validated | acc]}}
          error -> {:halt, error}
        end

      invalid, {:ok, _acc} ->
        {:halt, {:error, Error.validation_error("Expected Route struct", %{value: invalid})}}
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  def validate(invalid) do
    {:error,
     Error.validation_error("Expected Route struct or list of Route structs", %{value: invalid})}
  end

  @doc """
  Routes a signal through the router to find and execute matching handlers.

  ## Parameters
  - router: The router struct to use for routing
  - signal: The signal to route

  ## Returns

  * `{:ok, [term()]}` - List of matching targets, may be empty if no matches
  * `{:error, term()}` - Other errors that occurred during routing

  ## Examples

      {:ok, targets} = Router.route(router, %Signal{
        type: "payment.processed",
        data: %{amount: 100}
      })
  """
  @spec route(Router.t(), Signal.t()) :: {:ok, [term()]} | {:error, term()}
  def route(%Router{trie: _trie}, %Signal{type: nil}) do
    {:error, Error.routing_error("Signal type cannot be nil")}
  end

  def route(%Router{trie: trie}, %Signal{} = signal) do
    results = Engine.route_signal(trie, signal)

    if Enum.empty?(results) do
      {:error, Error.routing_error("No matching handlers found for signal")}
    else
      {:ok, results}
    end
  end

  @doc """
  Checks if a signal type matches a pattern.

  ## Parameters
  - type: The signal type to check (e.g. "user.created")
  - pattern: The pattern to match against (e.g. "user.*" or "audit.**")

  ## Returns
  - `true` if the type matches the pattern
  - `false` otherwise

  ## Examples

      iex> Router.matches?("user.created", "user.*")
      true

      iex> Router.matches?("audit.user.created", "audit.**")
      true

      iex> Router.matches?("user.created", "payment.*")
      false

      iex> Router.matches?("user.profile.updated", "user.*")
      false

      iex> Router.matches?(nil, "user.*")
      false

      iex> Router.matches?("user.created", nil)
      false
  """
  @spec matches?(String.t() | nil | any(), String.t() | nil | any()) :: boolean()
  def matches?(nil, _pattern), do: false
  def matches?(_type, nil), do: false
  def matches?(type, _pattern) when not is_binary(type), do: false
  def matches?(_type, pattern) when not is_binary(pattern), do: false

  def matches?(type, pattern) when is_binary(type) and is_binary(pattern) do
    # For single wildcards, verify segment count matches
    if String.contains?(pattern, "*") and not String.contains?(pattern, "**") do
      pattern_segments = String.split(pattern, ".")
      type_segments = String.split(type, ".")

      # Single wildcard must match exact number of segments
      if length(pattern_segments) != length(type_segments) do
        false
      else
        do_matches?(type, pattern)
      end
    else
      # For multi-level wildcards, handle empty segments
      if String.ends_with?(pattern, ".**") do
        pattern_base = String.replace_trailing(pattern, ".**", "")

        if String.starts_with?(type, pattern_base) do
          # The type matches the base pattern (everything before .**)
          remaining = String.replace_prefix(type, pattern_base, "")
          # Either there are no remaining segments or they start with a dot
          remaining == "" or String.starts_with?(remaining, ".")
        else
          false
        end
      else
        do_matches?(type, pattern)
      end
    end
  end

  defp do_matches?(type, pattern) do
    # Create a test signal with required fields
    test_signal = %Signal{
      type: type,
      source: "/test",
      id: Jido.Util.generate_id(),
      specversion: "1.0.2",
      data: %{}
    }

    # Create a test route with a dummy target
    test_route = %Route{
      path: pattern,
      target: {:noop, []},
      priority: 0
    }

    # Validate the pattern first
    case Validator.validate_path(pattern) do
      {:ok, _} ->
        # Build a trie with just this route
        trie = Engine.build_trie([test_route])

        # Route the signal and check if we got any matches
        case Engine.route_signal(trie, test_signal) do
          [] -> false
          _matches -> true
        end

      {:error, _} ->
        false
    end
  end

  @doc """
  Filters a list of signals based on a pattern.

  ## Parameters
  - signals: List of signals to filter
  - pattern: Pattern to filter by (e.g. "user.*" or "audit.**")

  ## Returns
  - List of signals whose types match the pattern

  ## Examples

      iex> signals = [
      ...>   %Signal{type: "user.created"},
      ...>   %Signal{type: "payment.processed"},
      ...>   %Signal{type: "user.updated"}
      ...> ]
      iex> Router.filter(signals, "user.*")
      [%Signal{type: "user.created"}, %Signal{type: "user.updated"}]

      iex> Router.filter(nil, "user.*")
      []

      iex> Router.filter([], nil)
      []

      iex> Router.filter("not a list", "user.*")
      []
  """
  @spec filter([Signal.t()] | nil | any(), String.t() | nil | any()) :: [Signal.t()]
  def filter(nil, _pattern), do: []
  def filter(_signals, nil), do: []
  def filter(signals, _pattern) when not is_list(signals), do: []
  def filter(_signals, pattern) when not is_binary(pattern), do: []

  def filter(signals, pattern) when is_list(signals) and is_binary(pattern) do
    # Validate the pattern first
    case Validator.validate_path(pattern) do
      {:ok, _} ->
        # Create a test route with a dummy target
        test_route = %Route{
          path: pattern,
          target: {:noop, []},
          priority: 0
        }

        # Build a trie with just this route
        trie = Engine.build_trie([test_route])

        # Filter signals by routing each one
        Enum.filter(signals, fn
          %Signal{type: nil} ->
            false

          signal ->
            case Engine.route_signal(trie, signal) do
              [] -> false
              _matches -> true
            end
        end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Checks if a route with the given ID exists in the router.

  ## Parameters
  - router: The router struct to check
  - route_id: The ID of the route to check for

  ## Returns
  - `true` if the route exists
  - `false` otherwise
  """
  @spec has_route?(Router.t(), String.t()) :: boolean()
  def has_route?(%Router{} = router, route_path) when is_binary(route_path) do
    case list(router) do
      {:ok, routes} -> Enum.any?(routes, fn route -> route.path == route_path end)
      _ -> false
    end
  end

  def has_route?(_router, _route_id), do: false
end
