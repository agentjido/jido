defmodule Jido.Signal.Router do
  use Private
  use ExDbug, enabled: true
  use TypedStruct
  alias Jido.Signal
  alias Jido.Instruction
  alias Jido.Error

  @valid_path_regex ~r/^[a-zA-Z0-9.*_-]+(\.[a-zA-Z0-9.*_-]+)*$/
  @default_priority 0
  @max_priority 100
  @min_priority -100

  @type match :: (Signal.t() -> boolean())
  @type priority :: non_neg_integer()
  @type wildcard_type :: :single | :multi

  @type route_spec ::
          {String.t(), Instruction.t()}
          | {String.t(), Instruction.t(), priority()}
          | {String.t(), match(), Instruction.t()}
          | {String.t(), match(), Instruction.t(), priority()}

  typedstruct module: HandlerInfo do
    @default_priority 0
    field(:instruction, Instruction.t(), enforce: true)
    field(:priority, Router.priority(), default: @default_priority)
    field(:complexity, non_neg_integer(), default: 0)
  end

  typedstruct module: PatternMatch do
    @default_priority 0
    field(:match, Router.match(), enforce: true)
    field(:instruction, Instruction.t(), enforce: true)
    field(:priority, Router.priority(), default: @default_priority)
  end

  typedstruct module: NodeHandlers do
    field(:handlers, [HandlerInfo.t()], default: [])
    field(:matchers, [PatternMatch.t()], default: [])
  end

  typedstruct module: WildcardHandlers do
    field(:type, Router.wildcard_type(), enforce: true)
    field(:handlers, NodeHandlers.t(), enforce: true)
  end

  typedstruct module: TrieNode do
    field(:segments, %{String.t() => TrieNode.t()}, default: %{})
    field(:wildcards, [WildcardHandlers.t()], default: [])
    field(:handlers, NodeHandlers.t())
  end

  typedstruct module: Route do
    @default_priority 0
    field(:path, String.t(), enforce: true)
    field(:instruction, Instruction.t(), enforce: true)
    field(:priority, Router.priority(), default: @default_priority)
    field(:match, Router.match())
  end

  typedstruct module: Router do
    field(:trie, TrieNode.t(), default: %TrieNode{})
    field(:route_count, non_neg_integer(), default: 0)
  end

  @doc """
  Creates a new router with the given routes.
  """
  @spec new(route_spec() | [route_spec()] | [Route.t()] | nil) ::
          {:ok, Router.t()} | {:error, term()}
  def new(nil), do: {:ok, %Router{}}

  def new(routes) do
    with {:ok, normalized} <- normalize(routes),
         {:ok, validated} <- validate(normalized) do
      trie = build_trie(validated)
      {:ok, %Router{trie: trie, route_count: length(validated)}}
    end
  end

  @doc """
  Normalizes route specifications into Route structs.

  ## Parameters
    * `input` - One of:
      * Single Route struct
      * List of Route structs
      * List of route_spec tuples
      * {path, instruction} tuple
      * {path, instruction, priority} tuple
      * {path, match_fn, instruction} tuple
      * {path, match_fn, instruction, priority} tuple

  ## Returns
    * `{:ok, [%Route{}]}` - List of normalized Route structs
    * `{:error, term()}` - If normalization fails
  """
  @spec normalize(route_spec() | [route_spec()] | [Route.t()]) ::
          {:ok, [Route.t()]} | {:error, term()}
  def normalize(input)

  def normalize(%Route{} = route), do: {:ok, [route]}

  def normalize(routes) when is_list(routes) do
    routes
    |> Enum.reduce_while({:ok, []}, fn
      %Route{} = route, {:ok, acc} ->
        {:cont, {:ok, [route | acc]}}

      {path, %Instruction{} = instruction}, {:ok, acc} ->
        route = %Route{path: path, instruction: instruction}
        {:cont, {:ok, [route | acc]}}

      {path, %Instruction{} = instruction, priority}, {:ok, acc}
      when is_integer(priority) ->
        route = %Route{path: path, instruction: instruction, priority: priority}
        {:cont, {:ok, [route | acc]}}

      {path, match_fn, %Instruction{} = instruction}, {:ok, acc}
      when is_function(match_fn, 1) ->
        route = %Route{path: path, instruction: instruction, match: match_fn}
        {:cont, {:ok, [route | acc]}}

      {path, match_fn, %Instruction{} = instruction, priority}, {:ok, acc}
      when is_function(match_fn, 1) and is_integer(priority) ->
        route = %Route{path: path, instruction: instruction, match: match_fn, priority: priority}
        {:cont, {:ok, [route | acc]}}

      invalid, {:ok, _acc} ->
        {:halt,
         {:error,
          Error.validation_error("Invalid route specification format", %{
            route: invalid,
            expected_formats: [
              "%Route{}",
              "{path, instruction}",
              "{path, instruction, priority}",
              "{path, match_fn, instruction}",
              "{path, match_fn, instruction, priority}"
            ]
          })}}
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  def normalize({_path, %Instruction{}} = route), do: normalize([route])
  def normalize({_path, %Instruction{}, _priority} = route), do: normalize([route])

  def normalize({_path, match_fn, %Instruction{}} = route) when is_function(match_fn, 1),
    do: normalize([route])

  def normalize({_path, match_fn, %Instruction{}, _priority} = route)
      when is_function(match_fn, 1),
      do: normalize([route])

  def normalize(invalid) do
    {:error, Error.validation_error("Invalid route specification format", %{route: invalid})}
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
    with {:ok, normalized} <- normalize(routes),
         {:ok, validated} <- validate(normalized) do
      new_trie = build_trie(validated, router.trie)
      {:ok, %Router{router | trie: new_trie, route_count: router.route_count + length(validated)}}
    end
  end

  def add(%Router{} = router, route) do
    add(router, [route])
  end

  @doc """
  Removes one or more routes from the router.

  ## Parameters
  - router: The existing router struct
  - paths: A path string or list of path strings to remove

  ## Returns
  `{:ok, updated_router}` or `{:error, reason}`

  ## Examples

      # Remove a single route
      {:ok, router} = Router.remove(router, "metrics.**")

      # Remove multiple routes
      {:ok, router} = Router.remove(router, ["audit.*", "user.created"])
  """
  @spec remove(Router.t(), String.t() | [String.t()]) :: {:ok, Router.t()} | {:error, term()}
  def remove(%Router{} = router, paths) when is_list(paths) do
    new_trie = Enum.reduce(paths, router.trie, &remove_path/2)
    route_count = count_routes(new_trie)
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
            {route.path, route.instruction, route.priority}

          match_fn when is_function(match_fn) ->
            {route.path, match_fn, route.instruction, route.priority}
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

  Returns a list of Route structs containing the path, instruction, priority and match function
  for each registered route.

  ## Returns
  `{:ok, [%Route{}]}` - List of Route structs

  ## Examples

      {:ok, routes} = Router.list(router)

      # Returns:
      [
        %Route{
          path: "user.created",
          instruction: %Instruction{action: MyApp.Actions.HandleUserCreated},
          priority: 0,
          match: nil
        },
        %Route{
          path: "payment.processed",
          instruction: %Instruction{action: MyApp.Actions.HandleLargePayment},
          priority: 90,
          match: #Function<1.123456789/1>
        }
      ]
  """
  @spec list(Router.t()) :: {:ok, [Route.t()]}
  def list(%Router{} = router) do
    routes = collect_routes(router.trie, [], "")
    {:ok, routes}
  end

  @doc """
  Validates one or more Route structs.

  ## Parameters
  - routes: A %Route{} struct or list of %Route{} structs to validate

  ## Returns
  - {:ok, %Route{}} - Single validated Route struct
  - {:ok, [%Route{}]} - List of validated Route structs
  - {:error, term()} - If validation fails
  """
  @spec validate(Route.t() | [Route.t()]) :: {:ok, Route.t() | [Route.t()]} | {:error, term()}
  def validate(%Route{} = route) do
    with {:ok, path} <- validate_path(route.path),
         {:ok, instruction} <- validate_instruction(route.instruction),
         {:ok, match} <- validate_match(route.match),
         {:ok, priority} <- validate_priority(route.priority) do
      {:ok,
       %Route{
         path: path,
         instruction: instruction,
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
    dbug("Invalid input - expected Route struct or list of Route structs", value: invalid)

    {:error,
     Error.validation_error("Expected Route struct or list of Route structs", %{value: invalid})}
  end

  @doc """
  Routes a signal through the router to find and execute matching handlers.

  ## Parameters
  - router: The router struct to use for routing
  - signal: The signal to route

  ## Returns
  - {:ok, [instruction]} - List of matching instructions, may be empty if no matches
  - {:error, term()} - Other errors that occurred during routing

  ## Examples

      {:ok, results} = Router.route(router, %Signal{
        type: "payment.processed",
        data: %{amount: 100}
      })
  """
  @spec route(Router.t(), Signal.t()) :: {:ok, [Instruction.t()]} | {:error, term()}
  def route(%Router{trie: trie}, %Signal{type: type} = signal) do
    dbug("Routing signal", type: type)

    results =
      type
      |> String.split(".")
      |> do_route(trie, signal, [])
      |> sort_and_execute(signal)

    if Enum.empty?(results) do
      dbug("No handlers found for signal", type: type)
      {:error, Error.routing_error(:no_handler)}
    else
      dbug("Successfully routed signal", type: type, handler_count: length(results))
      {:ok, results}
    end
  end

  private do
    # Validates a path string against the allowed format
    defp validate_path(path) when is_binary(path) do
      dbug("Validating path", path: path)

      cond do
        String.contains?(path, "..") ->
          dbug("Path contains double dots", path: path)
          {:error, Error.routing_error(:invalid_path_format)}

        String.match?(path, ~r/\*\*.*\*\*/) ->
          dbug("Path contains consecutive multi-level wildcards", path: path)
          {:error, Error.routing_error(:invalid_path_format)}

        not String.match?(path, @valid_path_regex) ->
          dbug("Path does not match regex", path: path)
          {:error, Error.routing_error(:invalid_path_format)}

        true ->
          dbug("Path validation successful", path: path)
          {:ok, path}
      end
    end

    defp validate_path(invalid) do
      dbug("Invalid path type", value: invalid)
      {:error, Error.routing_error(:invalid_path)}
    end

    # Validates that an instruction has a valid action
    defp validate_instruction(%Instruction{action: action} = instruction) when is_atom(action) do
      dbug("Instruction validation successful")
      {:ok, instruction}
    end

    defp validate_instruction(invalid) do
      dbug("Invalid instruction", value: invalid)
      {:error, Error.routing_error(:invalid_instruction)}
    end

    # Validates that a match function returns boolean for a test signal
    defp validate_match(nil) do
      dbug("No match function provided")
      {:ok, nil}
    end

    defp validate_match(match_fn) when is_function(match_fn, 1) do
      dbug("Validating match function")

      try do
        test_signal = %Signal{
          type: "",
          source: "",
          id: "",
          data: %{
            amount: 0,
            currency: "USD"
          }
        }

        dbug("Testing match function with test signal")

        case match_fn.(test_signal) do
          result when is_boolean(result) ->
            dbug("Match function validation successful")
            {:ok, match_fn}

          other ->
            dbug("Match function returned non-boolean", result: other)
            {:error, Error.routing_error(:invalid_match_function)}
        end
      rescue
        error ->
          dbug("Match function raised error", error: error)
          {:error, Error.routing_error(:invalid_match_function)}
      end
    end

    defp validate_match(invalid) do
      dbug("Invalid match function", value: invalid)
      {:error, Error.routing_error(:invalid_match_function)}
    end

    # Validates that a priority is within allowed bounds
    defp validate_priority(nil), do: {:ok, @default_priority}

    defp validate_priority(priority) when is_integer(priority) do
      dbug("Validating priority", priority: priority)

      cond do
        priority > @max_priority ->
          dbug("Priority too high", priority: priority, max: @max_priority)
          {:error, Error.routing_error({:priority_out_of_bounds, :too_high})}

        priority < @min_priority ->
          dbug("Priority too low", priority: priority, min: @min_priority)
          {:error, Error.routing_error({:priority_out_of_bounds, :too_low})}

        true ->
          dbug("Priority validation successful", priority: priority)
          {:ok, priority}
      end
    end

    defp validate_priority(invalid) do
      dbug("Invalid priority type", value: invalid)
      {:error, Error.routing_error(:invalid_priority)}
    end

    # Cleans up a path string by removing extra dots and whitespace
    defp sanitize_path(path) do
      dbug("Sanitizing path", original: path)

      sanitized =
        path
        |> String.trim()
        |> String.replace(~r/\.+/, ".")
        |> String.replace(~r/(^\.|\.$)/, "")

      dbug("Path sanitized", original: path, sanitized: sanitized)
      sanitized
    end

    # Builds the trie structure from validated routes
    defp build_trie(routes, base_trie \\ %TrieNode{}) do
      Enum.reduce(routes, base_trie, fn %Route{} = route, trie ->
        segments = route.path |> sanitize_path() |> String.split(".")

        case route.match do
          nil ->
            handler_info = %HandlerInfo{
              instruction: route.instruction,
              priority: route.priority,
              complexity: calculate_complexity(route.path)
            }

            do_add_path_route(segments, trie, handler_info)

          match_fn ->
            pattern_match = %PatternMatch{
              match: match_fn,
              instruction: route.instruction,
              priority: route.priority
            }

            do_add_pattern_route(segments, trie, pattern_match)
        end
      end)
    end

    # Core routing logic
    defp do_route([], %TrieNode{} = _trie, %Signal{} = _signal, acc) do
      dbug("Reached end of segments", accumulated: length(acc))
      acc
    end

    defp do_route([segment | rest] = segments, %TrieNode{} = trie, %Signal{} = signal, acc) do
      dbug("Routing segments", segments: segments)

      # First try exact match
      matching_handlers =
        case Map.get(trie.segments, segment) do
          nil ->
            dbug("No exact match found for segment", segment: segment)
            acc

          %TrieNode{} = node ->
            handlers = collect_handlers(node.handlers, signal, acc)

            if rest == [] do
              dbug("Found leaf node", segment: segment)
              handlers
            else
              dbug("Found branch node", segment: segment)
              do_route(rest, node, signal, handlers)
            end
        end

      # Then try single wildcard
      matching_handlers =
        case Map.get(trie.segments, "*") do
          nil ->
            dbug("No single wildcard match found for segment", segment: segment)
            matching_handlers

          %TrieNode{} = node ->
            dbug("Found single wildcard match", segment: segment)
            handlers = collect_handlers(node.handlers, signal, matching_handlers)

            if rest == [] do
              handlers
            else
              do_route(rest, node, signal, handlers)
            end
        end

      # Finally try multi-level wildcard
      case Map.get(trie.segments, "**") do
        nil ->
          dbug("No multi-level wildcard match found for segment", segment: segment)
          matching_handlers

        %TrieNode{} = node ->
          dbug("Found multi-level wildcard match", segment: segment)
          handlers = collect_handlers(node.handlers, signal, matching_handlers)

          # Try all possible remaining segment combinations
          [rest, []]
          |> Stream.concat(tails(rest))
          |> Enum.reduce(handlers, fn remaining, acc ->
            if remaining == [] do
              acc
            else
              do_route(remaining, node, signal, acc)
            end
          end)
      end
    end

    # Helper to get all possible tails of a list
    defp tails([]), do: []
    defp tails([_h | t]), do: [t | tails(t)]

    # Handler collection logic
    defp collect_handlers(%NodeHandlers{} = node_handlers, %Signal{} = signal, acc) do
      dbug("Collecting handlers")

      handler_results =
        case node_handlers.handlers do
          handlers when is_list(handlers) ->
            Enum.map(handlers, fn info ->
              dbug("Found handler", priority: info.priority, complexity: info.complexity)
              {info.instruction, info.priority, info.complexity}
            end)

          _ ->
            []
        end

      pattern_results = collect_pattern_matches(node_handlers.matchers || [], signal)
      dbug("Collected pattern matches", count: length(pattern_results))

      handler_results ++ pattern_results ++ acc
    end

    defp collect_handlers(nil, %Signal{} = _signal, acc) do
      dbug("No handlers to collect")
      acc
    end

    # Pattern matching
    defp collect_pattern_matches(matchers, %Signal{} = signal) do
      dbug("Collecting pattern matches", count: length(matchers))

      Enum.reduce(matchers, [], fn %PatternMatch{} = matcher, matches ->
        dbug("Testing pattern", priority: matcher.priority)

        try do
          case matcher.match.(signal) do
            true ->
              dbug("Pattern matched", priority: matcher.priority)
              [{matcher.instruction, matcher.priority, 0} | matches]

            false ->
              dbug("Pattern did not match", priority: matcher.priority)
              matches

            _ ->
              dbug("Pattern returned non-boolean", priority: matcher.priority)
              matches
          end
        rescue
          _ ->
            dbug("Pattern match failed", priority: matcher.priority)
            matches
        end
      end)
    end

    # Handler execution
    defp sort_and_execute(handlers, %Signal{} = _signal) do
      dbug("Sorting and executing handlers", count: length(handlers))

      handlers
      |> Enum.sort_by(
        fn {_instruction, priority, complexity} ->
          # Sort by complexity first, then priority
          {complexity, priority}
        end,
        :desc
      )
      |> Enum.map(fn {instruction, _priority, _complexity} -> instruction end)
    end

    defp calculate_complexity(path) do
      segments = String.split(path, ".")

      # Base score from segment count (increase multiplier)
      base_score = length(segments) * 2000

      # Exact segment matches are worth more at start of path
      exact_matches =
        Enum.with_index(segments)
        |> Enum.reduce(0, fn {segment, index}, acc ->
          case segment do
            "**" -> acc
            "*" -> acc
            # Higher weight for exact matches
            _ -> acc + 3000 * (length(segments) - index)
          end
        end)

      # Penalty calculation with position weighting
      penalties =
        Enum.with_index(segments)
        |> Enum.reduce(0, fn {segment, index}, acc ->
          case segment do
            # Double wildcard has massive penalty, reduced if it comes after exact matches
            "**" -> acc + 2000 - index * 200
            # Single wildcard has smaller penalty
            "*" -> acc + 1000 - index * 100
            _ -> acc
          end
        end)

      base_score + exact_matches - penalties
    end

    # Route addition to trie
    defp do_add_path_route([segment], %TrieNode{} = trie, %HandlerInfo{} = handler_info) do
      dbug("Adding leaf handler", segment: segment, priority: handler_info.priority)

      Map.update(
        trie,
        :segments,
        %{segment => %TrieNode{handlers: %NodeHandlers{handlers: [handler_info]}}},
        fn segments ->
          Map.update(
            segments,
            segment,
            %TrieNode{handlers: %NodeHandlers{handlers: [handler_info]}},
            fn node ->
              %TrieNode{
                node
                | handlers: %NodeHandlers{
                    handlers: (node.handlers.handlers || []) ++ [handler_info],
                    matchers: node.handlers.matchers
                  }
              }
            end
          )
        end
      )
    end

    defp do_add_path_route([segment | rest], %TrieNode{} = trie, %HandlerInfo{} = handler_info) do
      dbug("Adding branch segment", segment: segment)

      Map.update(
        trie,
        :segments,
        %{segment => do_add_path_route(rest, %TrieNode{}, handler_info)},
        fn segments ->
          Map.update(
            segments,
            segment,
            do_add_path_route(rest, %TrieNode{}, handler_info),
            fn node -> do_add_path_route(rest, node, handler_info) end
          )
        end
      )
    end

    defp do_add_pattern_route([segment], %TrieNode{} = trie, %PatternMatch{} = matcher) do
      dbug("Adding leaf pattern matcher", segment: segment)

      Map.update(
        trie,
        :segments,
        %{segment => %TrieNode{handlers: %NodeHandlers{matchers: [matcher]}}},
        fn segments ->
          Map.update(
            segments,
            segment,
            %TrieNode{handlers: %NodeHandlers{matchers: [matcher]}},
            fn node ->
              %TrieNode{
                node
                | handlers: %NodeHandlers{matchers: (node.handlers.matchers || []) ++ [matcher]}
              }
            end
          )
        end
      )
    end

    defp do_add_pattern_route([segment | rest], %TrieNode{} = trie, %PatternMatch{} = matcher) do
      dbug("Adding pattern branch segment", segment: segment)

      Map.update(
        trie,
        :segments,
        %{segment => do_add_pattern_route(rest, %TrieNode{}, matcher)},
        fn segments ->
          Map.update(
            segments,
            segment,
            do_add_pattern_route(rest, %TrieNode{}, matcher),
            fn node -> do_add_pattern_route(rest, node, matcher) end
          )
        end
      )
    end

    # Removes a path from the trie
    defp remove_path(path, trie) do
      segments = path |> sanitize_path() |> String.split(".")
      do_remove_path(segments, trie)
    end

    # Recursively removes a path from the trie
    defp do_remove_path([], trie), do: trie

    defp do_remove_path([segment], %TrieNode{segments: segments} = trie) do
      # Remove the leaf node
      new_segments = Map.delete(segments, segment)
      %TrieNode{trie | segments: new_segments}
    end

    defp do_remove_path([segment | rest], %TrieNode{segments: segments} = trie) do
      case Map.get(segments, segment) do
        nil ->
          trie

        node ->
          new_node = do_remove_path(rest, node)
          # If the node is empty after removal, remove it too
          if map_size(new_node.segments) == 0 do
            %TrieNode{trie | segments: Map.delete(segments, segment)}
          else
            %TrieNode{trie | segments: Map.put(segments, segment, new_node)}
          end
      end
    end

    # Counts total routes in the trie
    defp count_routes(%TrieNode{segments: segments, handlers: handlers}) do
      handler_count =
        case handlers do
          %NodeHandlers{handlers: handlers} when is_list(handlers) ->
            length(handlers)

          _ ->
            0
        end

      Enum.reduce(segments, handler_count, fn {_segment, node}, acc ->
        acc + count_routes(node)
      end)
    end

    # Collects all routes from the trie into a list of Route structs
    defp collect_routes(%TrieNode{segments: segments, handlers: handlers}, acc, path_prefix) do
      # Add any handlers at current node
      acc =
        case handlers do
          %NodeHandlers{handlers: handlers} when is_list(handlers) and length(handlers) > 0 ->
            # Preserve order by not reversing here
            Enum.map(handlers, fn %HandlerInfo{
                                    instruction: instruction,
                                    priority: priority
                                  } ->
              %Route{
                path: String.trim_leading(path_prefix, "."),
                instruction: instruction,
                priority: priority
              }
            end) ++ acc

          %NodeHandlers{matchers: matchers} when is_list(matchers) and length(matchers) > 0 ->
            # Preserve order by not reversing here
            Enum.map(matchers, fn %PatternMatch{
                                    instruction: instruction,
                                    priority: priority,
                                    match: match
                                  } ->
              %Route{
                path: String.trim_leading(path_prefix, "."),
                instruction: instruction,
                priority: priority,
                match: match
              }
            end) ++ acc

          _ ->
            acc
        end

      # Recursively collect from child nodes
      segments
      # Sort segments for consistent ordering
      |> Enum.sort()
      |> Enum.reduce(acc, fn {segment, node}, acc ->
        new_prefix = path_prefix <> "." <> segment
        collect_routes(node, acc, new_prefix)
      end)
    end
  end
end
