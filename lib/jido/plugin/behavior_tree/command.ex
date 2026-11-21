defmodule Jido.Plugin.BehaviorTree.Command do
  @moduledoc false

  alias Jido.BehaviorTree.{Blackboard, Tick, Tree}
  alias Jido.Joi
  alias Jido.Plugin.BehaviorTree, as: Plugin
  alias Jido.Plugin.BehaviorTree.StateUpdate

  use Jido.Action,
    name: "behavior_tree_command",
    schema: Joi.map()

  @inputs %{
    "jido.bt.tick" => Joi.object(%{}, unrecognized_keys: :error),
    "jido.bt.halt" => Joi.object(%{}, unrecognized_keys: :error),
    "jido.bt.reset" => Joi.object(%{}, unrecognized_keys: :error),
    "jido.bt.blackboard.put" => Joi.object(%{key: Joi.any(), value: Joi.any()}, unrecognized_keys: :error),
    "jido.bt.blackboard.merge" => Joi.object(%{data: Joi.map()}, unrecognized_keys: :error)
  }

  @impl true
  def run(params, %{agent_state: %{behavior_tree: state}, plugin_inputs: inputs, signal: %{type: type}} = context)
      when is_map_key(@inputs, type) do
    with {:ok, params} <- Jido.Agent.Directive.parse(Map.fetch!(@inputs, type), params),
         {:ok, tree_state, agent_state, directives} <- execute(type, params, state, context, inputs[Plugin].prepared) do
      {:ok, agent_state, [%StateUpdate{state: tree_state} | directives]}
    end
  end

  defp execute("jido.bt.tick", _params, state, context, config) do
    tick_context = Map.put(context, :plugin, Plugin)
    tick = %{Tick.new_with_context(state.blackboard, nil, [], tick_context) | sequence: state.tick_count}

    case Tree.tick_with_context(state.tree, tick) do
      {{:error, reason}, _tree, _tick} ->
        {:error, reason}

      {status, tree, tick} when status in [:running, :success, :failure] ->
        tree = if config.reset_on_completion and status != :running, do: Tree.halt(tree), else: tree
        updated = %{state | tree: tree, blackboard: tick.blackboard, status: status, tick_count: state.tick_count + 1}
        {:ok, updated, tick.context.agent_state, tick.directives}
    end
  end

  defp execute(type, params, state, context, config) do
    updated =
      case {type, params} do
        {"jido.bt.halt", _} ->
          %{state | tree: Tree.halt(state.tree), status: :idle}

        {"jido.bt.reset", _} ->
          _halted = Tree.halt(state.tree)
          %{state | tree: config.tree, blackboard: Blackboard.new(config.blackboard), status: :idle, tick_count: 0}

        {"jido.bt.blackboard.put", %{key: key, value: value}} ->
          %{state | blackboard: Blackboard.put(state.blackboard, key, value)}

        {"jido.bt.blackboard.merge", %{data: data}} ->
          %{state | blackboard: Blackboard.merge(state.blackboard, data)}
      end

    {:ok, updated, context.agent_state, []}
  end
end
