defmodule Jido.AgentServer.SignalRouter do
  @moduledoc """
  Builds a unified Jido.Signal.Router from strategy, agent, and plugin routes.

  This module is responsible for:
  1. Collecting routes from all sources (strategy, agent, plugins)
  2. Normalizing route specs with appropriate priorities
  3. Building the trie-based router for efficient signal routing

  ## Priority Levels

  | Source   | Default Priority | Range    |
  |----------|------------------|----------|
  | Strategy | 50               | 50-100   |
  | Agent    | 0                | -25 to 25|
  | Plugin   | -10              | -50 to -10|

  ## Route Spec Formats

  Routes can be specified in several formats:
  - `{path, target}` - Simple route with default priority
  - `{path, target, priority}` - Route with explicit priority
  - `{path, match_fn, target}` - Route with match function
  - `{path, match_fn, target, priority}` - Route with match function and priority

  ## Target Types

  - `module()` - Action module, params = signal.data
  - `{module(), map()}` - Action module with static params
  - `{:strategy_cmd, atom()}` - Strategy command
  """

  alias Jido.AgentServer.State
  alias Jido.Signal.Router, as: SignalRouter

  @strategy_default_priority 50
  @agent_default_priority 0
  @plugin_default_priority -10

  @doc """
  Builds a unified router from all route sources in the agent state.

  Collects routes from:
  - Strategy routes (priority 50+) via `strategy.signal_routes/1`
  - Agent routes (priority 0) via `agent_module.signal_routes/1`
  - Plugin routes (priority -10) via plugin `signal_patterns` and `signal_routes/1`

  Returns an empty router if no routes are found or if building fails.
  """
  @spec build(State.t()) :: SignalRouter.Router.t()
  def build(%State{} = state) do
    routes =
      []
      |> add_strategy_routes(state)
      |> add_agent_routes(state)
      |> add_plugin_routes(state)

    case SignalRouter.new(routes) do
      {:ok, router} -> router
      {:error, _} -> SignalRouter.new!([])
    end
  end

  # Collects routes from strategy.signal_routes/1
  defp add_strategy_routes(routes, %State{agent_module: agent_module}) do
    strat = agent_module.strategy()
    ctx = %{agent_module: agent_module, strategy_opts: agent_module.strategy_opts()}

    if function_exported?(strat, :signal_routes, 1) do
      strategy_routes = strat.signal_routes(ctx)
      normalized = normalize_routes(strategy_routes, @strategy_default_priority)
      routes ++ normalized
    else
      routes
    end
  end

  # Collects routes from agent_module.signal_routes/1
  defp add_agent_routes(routes, %State{agent_module: agent_module}) do
    if function_exported?(agent_module, :signal_routes, 1) do
      ctx = %{agent_module: agent_module}
      agent_routes = agent_module.signal_routes(ctx)
      normalized = normalize_routes(agent_routes, @agent_default_priority)
      routes ++ normalized
    else
      routes
    end
  end

  # Collects routes from plugins via plugin_routes/0 (pre-expanded) or fallback to signal_routes/1
  defp add_plugin_routes(routes, %State{agent_module: agent_module}) do
    # First, try to get pre-expanded routes from plugin_routes/0 (Phase 3 approach)
    pre_expanded_routes =
      if function_exported?(agent_module, :plugin_routes, 0) do
        agent_module.plugin_routes()
      else
        []
      end

    # Get custom routes from plugins that define signal_routes/1 callback (legacy support)
    plugin_specs =
      if function_exported?(agent_module, :plugin_specs, 0) do
        agent_module.plugin_specs()
      else
        []
      end

    custom_routes =
      Enum.flat_map(plugin_specs, fn spec ->
        get_plugin_custom_routes(spec)
      end)

    # Combine: pre-expanded routes are already normalized with priority
    # Custom routes need normalization
    normalized_custom = normalize_routes(custom_routes, @plugin_default_priority)

    routes ++ pre_expanded_routes ++ normalized_custom
  end

  defp get_plugin_custom_routes(spec) do
    plugin_module = spec.module

    if function_exported?(plugin_module, :signal_routes, 1) do
      case plugin_module.signal_routes(spec.config) do
        [] -> []
        routes when is_list(routes) -> routes
        _other -> []
      end
    else
      []
    end
  end

  defp normalize_routes(routes, default_priority) do
    Enum.map(routes, fn
      {path, target, priority} when is_integer(priority) ->
        {path, target, priority}

      {path, match_fn, target, priority} when is_function(match_fn, 1) and is_integer(priority) ->
        {path, match_fn, target, priority}

      {path, match_fn, target} when is_function(match_fn, 1) ->
        {path, match_fn, target, default_priority}

      {path, target} ->
        {path, target, default_priority}
    end)
  end
end
