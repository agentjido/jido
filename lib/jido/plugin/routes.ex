defmodule Jido.Plugin.Routes do
  @moduledoc """
  Utilities for expanding and validating plugin routes.

  This module handles:
  - Expanding plugin routes with instance prefixes
  - Detecting route conflicts at compile time
  - Merging routes with priority-based resolution

  ## Route Formats

  Routes can be specified in several formats:

  - `{path, target}` - Simple route with default options
  - `{path, target, opts}` - Route with options like `priority:` or `on_conflict:`

  ## Conflict Detection

  Routes conflict when they have the same signal type. Resolution:

  - Same priority + no `:on_conflict` => error
  - Different priority => higher priority wins (not a conflict)
  - Route with `on_conflict: :replace` => overrides without error

  ## Priority Levels

  Default priority for plugin routes is -10 (from signal router conventions).
  """

  alias Jido.Plugin.Instance

  @plugin_default_priority -10

  @doc """
  Expands routes from a plugin instance, applying the route prefix.

  Takes a plugin instance and returns expanded route tuples where
  each route path is prefixed with the instance's `route_prefix`.

  ## Route Input Formats

  - `{"post", ActionModule}` => `{"slack.post", ActionModule, []}`
  - `{"post", ActionModule, priority: 5}` => `{"slack.post", ActionModule, [priority: 5]}`
  - `{"post", ActionModule, on_conflict: :replace}` => with option preserved

  ## Legacy Support

  If `manifest.signal_routes` is empty but `manifest.signal_patterns` exists,
  routes are generated from patterns + actions.

  ## Examples

      iex> instance = Instance.new(SlackPlugin)  # route_prefix: "slack"
      iex> expand_routes(instance)
      [{"slack.post", SlackActions.Post, []}, {"slack.list", SlackActions.List, []}]

      iex> instance = Instance.new({SlackPlugin, as: :support})  # route_prefix: "support.slack"
      iex> expand_routes(instance)
      [{"support.slack.post", SlackActions.Post, []}, ...]
  """
  @spec expand_routes(Instance.t()) :: [{String.t(), module(), keyword()}]
  def expand_routes(%Instance{} = instance) do
    manifest = instance.manifest
    prefix = instance.route_prefix
    module = instance.module

    routes = manifest.signal_routes || []

    expanded =
      cond do
        routes != [] ->
          Enum.map(routes, fn route -> expand_route(route, prefix) end)

        has_custom_signal_routes?(module) ->
          []

        true ->
          expand_legacy_routes(manifest, prefix)
      end

    expanded
  end

  defp has_custom_signal_routes?(module) do
    if function_exported?(module, :signal_routes, 1) do
      case module.signal_routes(%{}) do
        [] -> false
        routes when is_list(routes) -> true
        _ -> false
      end
    else
      false
    end
  end

  @doc """
  Detects conflicts in a list of expanded routes from all plugin instances.

  Returns `{:ok, merged_routes}` if no conflicts, or
  `{:error, conflicts}` with a list of conflict descriptions.

  ## Conflict Rules

  - Same signal type + same priority (no `:on_conflict`) => conflict error
  - Same signal type + different priority => higher priority wins
  - Route with `on_conflict: :replace` => overrides without error

  ## Examples

      iex> routes = [
      ...>   {"slack.post", Action1, []},
      ...>   {"slack.list", Action2, []}
      ...> ]
      iex> detect_conflicts(routes)
      {:ok, [{"slack.post", Action1, -10}, {"slack.list", Action2, -10}]}

      iex> routes = [
      ...>   {"slack.post", Action1, []},
      ...>   {"slack.post", Action2, []}  # same path, same default priority
      ...> ]
      iex> detect_conflicts(routes)
      {:error, ["Route conflict: 'slack.post' defined multiple times with same priority -10"]}
  """
  @spec detect_conflicts([{String.t(), module(), keyword()}]) ::
          {:ok, [{String.t(), module(), integer()}]} | {:error, [String.t()]}
  def detect_conflicts(routes) when is_list(routes) do
    routes_with_priority =
      Enum.map(routes, fn {path, target, opts} ->
        priority = Keyword.get(opts, :priority, @plugin_default_priority)
        on_conflict = Keyword.get(opts, :on_conflict)
        {path, target, priority, on_conflict}
      end)

    grouped = Enum.group_by(routes_with_priority, fn {path, _, _, _} -> path end)

    {merged, conflicts} =
      Enum.reduce(grouped, {[], []}, fn {path, path_routes}, {acc_merged, acc_conflicts} ->
        case resolve_path_routes(path, path_routes) do
          {:ok, resolved} ->
            {[resolved | acc_merged], acc_conflicts}

          {:error, conflict_msg} ->
            {acc_merged, [conflict_msg | acc_conflicts]}
        end
      end)

    if conflicts == [] do
      final_routes =
        merged
        |> Enum.reverse()
        |> Enum.map(fn {path, target, priority, _on_conflict} ->
          {path, target, priority}
        end)

      {:ok, final_routes}
    else
      {:error, Enum.reverse(conflicts)}
    end
  end

  @doc """
  Returns the default priority for plugin routes.
  """
  @spec default_priority() :: integer()
  def default_priority, do: @plugin_default_priority

  @doc """
  Generates route tuples from a cartesian product of signal patterns and action modules.

  This is the explicit replacement for the implicit `signal_patterns × actions`
  expansion that was previously built into the plugin compile-time option.

  ## Examples

      iex> Routes.from_patterns(["chat.*"], [SendMessage, ListHistory])
      [{"chat.*", SendMessage}, {"chat.*", ListHistory}]

      iex> Routes.from_patterns(["chat.send"], [SendMessage])
      [{"chat.send", SendMessage}]
  """
  @spec from_patterns([String.t()], [module()]) :: [{String.t(), module()}]
  def from_patterns(patterns, actions) when is_list(patterns) and is_list(actions) do
    for pattern <- patterns, action <- actions, do: {pattern, action}
  end

  defp expand_route({path, target}, prefix) do
    {prefix_path(prefix, path), target, []}
  end

  defp expand_route({path, target, opts}, prefix) when is_list(opts) do
    {prefix_path(prefix, path), target, opts}
  end

  defp expand_route({path, target, priority}, prefix) when is_integer(priority) do
    {prefix_path(prefix, path), target, [priority: priority]}
  end

  defp expand_legacy_routes(manifest, prefix) do
    patterns = manifest.signal_patterns || []
    actions = manifest.actions || []

    for pattern <- patterns, action <- actions do
      prefixed_pattern = prefix_path(prefix, pattern)
      {prefixed_pattern, action, []}
    end
  end

  defp prefix_path(prefix, path) do
    "#{prefix}.#{path}"
  end

  defp resolve_path_routes(_path, routes) when length(routes) == 1 do
    {:ok, hd(routes)}
  end

  defp resolve_path_routes(path, routes) do
    replace_routes =
      Enum.filter(routes, fn {_, _, _, on_conflict} -> on_conflict == :replace end)

    if replace_routes != [] do
      winner = Enum.max_by(replace_routes, fn {_, _, priority, _} -> priority end)
      {:ok, winner}
    else
      resolve_by_priority(path, routes)
    end
  end

  defp resolve_by_priority(path, routes) do
    sorted = Enum.sort_by(routes, fn {_, _, priority, _} -> priority end, :desc)
    [highest | rest] = sorted

    {_, _, highest_priority, _} = highest
    same_priority = Enum.filter(rest, fn {_, _, p, _} -> p == highest_priority end)

    if same_priority == [] do
      {:ok, highest}
    else
      build_conflict_error(path, highest, same_priority, highest_priority)
    end
  end

  defp build_conflict_error(path, highest, same_priority, priority) do
    targets =
      Enum.map_join([highest | same_priority], ", ", fn {_, target, _, _} ->
        inspect(target)
      end)

    {:error,
     "Route conflict: '#{path}' defined multiple times with same priority #{priority} (targets: #{targets})"}
  end
end
