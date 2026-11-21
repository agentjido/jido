defmodule Jido.Plugin.BehaviorTree do
  @moduledoc """
  Runs a Behavior Tree as part of a Jido Agent Turn.

  Enable the Plugin with `plugins: [{Jido.Plugin.BehaviorTree, %{tree: tree}}]`.
  The Plugin contributes the five `jido.bt.*` routes and stores the tree
  continuation, blackboard, status, and tick count in `state.behavior_tree`.
  Send one tick Signal for each traversal.
  """

  use Jido.Plugin, option_keys: [agent: [:tree, :blackboard, :reset_on_completion]]

  alias Jido.Agent.Schema
  alias Jido.BehaviorTree.{Blackboard, Tree}
  alias Jido.{Error, Joi}
  alias Jido.Plugin.BehaviorTree.{Command, StateUpdate}

  @routes [
    {"jido.bt.tick", :bt_tick},
    {"jido.bt.halt", :bt_halt},
    {"jido.bt.reset", :bt_reset},
    {"jido.bt.blackboard.put", :bt_blackboard_put},
    {"jido.bt.blackboard.merge", :bt_blackboard_merge}
  ]

  @config_keys [:tree, :blackboard, :reset_on_completion]
  @config_schema Joi.object(
                   %{
                     tree: Joi.struct(Tree),
                     blackboard: Joi.map() |> Joi.default(%{}),
                     reset_on_completion: Joi.boolean() |> Joi.default(false)
                   },
                   unrecognized_keys: :error
                 )

  @doc false
  @impl Jido.Agent.Extension
  def normalize(data) do
    with {:ok, config} <- Schema.fields(data, @config_keys, %{}),
         {:ok, config} <- Jido.Agent.Directive.parse(@config_schema, config),
         :ok <- validate_tree(config.tree),
         :ok <- Schema.plain_map(config.blackboard),
         :ok <- Schema.static(config) do
      {:ok, config}
    end
  end

  @doc false
  @impl Jido.Agent.Extension
  def derive_routes(_data) do
    Enum.map(@routes, fn {path, name} ->
      %{path: path, as: name, handler: %{kind: :action, target: Command}}
    end)
  end

  @doc false
  @impl true
  def prepare(%{signal: %{type: type}}, opts) when type in ["jido.bt.tick", "jido.bt.reset"] do
    {:ok, Map.new(opts)}
  end

  def prepare(_preparation, _opts), do: {:ok, nil}

  @doc false
  @impl true
  def state_spec(opts) do
    initial = %{
      tree: Keyword.fetch!(opts, :tree),
      blackboard: Blackboard.new(Keyword.fetch!(opts, :blackboard)),
      status: :idle,
      tick_count: 0
    }

    {:behavior_tree, StateUpdate.state_schema() |> Joi.default(initial)}
  end

  @doc false
  @impl true
  def directives(_opts), do: [StateUpdate]

  @doc false
  @impl true
  def reduce(reduction, _opts) do
    case Enum.filter(reduction.directives, &is_struct(&1, StateUpdate)) do
      [] ->
        {:ok, reduction.plugin_state}

      [%StateUpdate{state: state}] ->
        {:ok, state}

      _updates ->
        Error.validation_result(:duplicate_tree_update, [], "A Turn can update the behavior tree once")
    end
  end

  @doc false
  @impl true
  def dispatch(_runtime, %StateUpdate{}, _context, _opts), do: :ok

  defp validate_tree(tree) do
    if Tree.valid?(tree) do
      :ok
    else
      Error.validation_result(:invalid_behavior_tree, [:tree], "Expected a tree of Behavior Tree nodes")
    end
  end
end
