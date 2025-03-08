defimpl Inspect, for: Jido.Signal.Router.Router do
  def inspect(router, opts) do
    # Check if verbose option is set in the inspect options
    case Keyword.get(opts.custom_options, :verbose, false) do
      true ->
        # Use the default inspecting behavior for verbose mode
        Inspect.Any.inspect(router, opts)

      false ->
        # Get the routes in a simplified format
        {:ok, routes} = Jido.Signal.Router.list(router)

        # Format each route as a simplified string
        formatted_routes =
          Enum.map(routes, fn route ->
            priority_str = if route.priority != 0, do: " (priority: #{route.priority})", else: ""
            matcher_str = if route.match, do: " [with matcher]", else: ""

            # Format the target more concisely
            target_str =
              case route.target do
                %Jido.Instruction{} = instruction ->
                  "→ %Instruction{action: #{inspect(instruction.action)}}"

                {adapter, opts} when is_atom(adapter) ->
                  "→ {#{inspect(adapter)}, #{inspect(opts)}}"

                targets when is_list(targets) ->
                  "→ [#{Enum.count(targets)} dispatchers]"

                other ->
                  "→ #{inspect(other)}"
              end

            "  #{route.path}#{matcher_str}#{priority_str} #{target_str}"
          end)

        # Assemble the final string
        routes_str = Enum.join(formatted_routes, "\n")

        # Create the final inspect string
        "#Router<routes: #{router.route_count}>\n#{routes_str}"
    end
  end
end
