defimpl Inspect, for: Jido.Signal.Router.Router do
  def inspect(router, opts) do
    if Keyword.get(opts.custom_options, :verbose, false) do
      Inspect.Any.inspect(router, opts)
    else
      format_router_summary(router)
    end
  end

  # Formats the router as a concise summary
  defp format_router_summary(router) do
    {:ok, routes} = Jido.Signal.Router.list(router)
    formatted_routes = Enum.map(routes, &format_route/1)
    routes_str = Enum.join(formatted_routes, "\n")
    "#Router<routes: #{Jido.Signal.Router.count(router)}>\n#{routes_str}"
  end

  # Formats a single route
  defp format_route(route) do
    priority_str = format_priority(route.priority)
    matcher_str = format_matcher(route.match)
    target_str = format_target(route.target)
    "  #{route.path}#{matcher_str}#{priority_str} #{target_str}"
  end

  defp format_priority(0), do: ""
  defp format_priority(priority), do: " (priority: #{priority})"

  defp format_matcher(nil), do: ""
  defp format_matcher(_), do: " [with matcher]"

  # Formats target based on its type
  defp format_target({adapter, opts}) when is_atom(adapter) do
    "→ {#{inspect(adapter)}, #{inspect(opts)}}"
  end

  defp format_target(targets) when is_list(targets) and is_integer(length(targets)) do
    "→ [#{Enum.count(targets)} items]"
  end

  defp format_target(%{__struct__: module}) do
    "→ %#{inspect(module)}{}"
  end

  defp format_target(atom) when is_atom(atom) do
    "→ #{inspect(atom)}"
  end

  defp format_target(other) do
    "→ #{inspect(other)}"
  end
end
