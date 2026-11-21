defmodule Jido.BehaviorTree.DSL do
  @moduledoc """
  Defines named trees with the same nodes used by the Behavior Tree executor.

  Use this DSL at module scope. Each `tree` declaration defines a zero-argument
  function. Pass its result to the Agent Plugin, standalone executor, or tool
  wrapper. In an Agent module, put a `behavior_tree` block after `use Jido.Agent`
  to define the tree and enable the Plugin.

      defmodule Reservations.Tree do
        use Jido.BehaviorTree.DSL

        tree :reservation do
          sequence :reserve do
            condition :has_stock, blackboard(:quantity) > 0
            action :record, amount <- blackboard(:quantity) * 2 do
              {:ok, %{reserved: amount}}
            end
          end
        end
      end

  Conditions, Action params, and inline Action bindings use `Jido.Expr`.
  Use `blackboard(key)` or `state(key)` to read a required value when the node
  runs. `state(key)` reads the current candidate Agent state. Missing state or
  keys cause a tick error. Inline Action bodies are ordinary Elixir. They can
  call private functions in the owner module.
  An inline Action can take `inline: [schema: ..., context: variable]`.
  Use `node :name, expression` to insert a custom node or subtree root.
  """

  alias Jido.Action.Inline
  alias Jido.Agent.DSL, as: AgentDSL
  alias Jido.BehaviorTree.{Expression, Tree}
  alias Jido.BehaviorTree.Nodes.{Action, Condition, Named, Selector, Sequence, Wait}
  alias Jido.Instruction.Config
  alias Jido.Plugin.BehaviorTree

  @branches %{sequence: Sequence, selector: Selector}
  @inline_fields [:name, :description, :schema, :output_schema, :context]

  @doc false
  defmacro __using__(_opts) do
    quote do
      use Jido.Action.Inline
      import Jido.BehaviorTree.DSL, only: [tree: 2, behavior_tree: 2, behavior_tree: 3]
    end
  end

  @doc "Defines a named tree function with exactly one root node."
  defmacro tree(name, do: body), do: compile_tree(name, body, __CALLER__, nil)

  @doc """
  Defines a named tree and enables the Behavior Tree Plugin in the current Agent.

  Declare one block after `use Jido.Agent`. Options are `:blackboard` and
  `:reset_on_completion`. The block also defines a function that returns the tree.
  """
  defmacro behavior_tree(name, options \\ [], do: body) do
    options!(options, [:blackboard, :reset_on_completion], __CALLER__)

    registration =
      quote do
        config = Map.put(unquote({:%{}, [], options}), :tree, @__jido_behavior_tree__)
        AgentDSL.register_plugin!({BehaviorTree, config}, __ENV__)
      end

    compile_tree(name, body, __CALLER__, registration)
  end

  defp compile_tree(name, body, caller, registration) do
    unless caller.module && is_nil(caller.function) && valid_name?(name) do
      Config.compile_error!(caller, "declare a tree with a literal atom name at module scope")
    end

    {root, declarations} =
      case children(body, [name], caller) do
        {[root], declarations} -> {root, declarations}
        _ -> Config.compile_error!(caller, "tree #{inspect(name)} requires exactly one root node")
      end

    quote line: caller.line do
      if Module.defines?(__MODULE__, {unquote(name), 0}) do
        Jido.Instruction.Config.compile_error!(__ENV__, "duplicate tree function #{unquote(name)}/0")
      end

      unquote_splicing(declarations)

      @__jido_behavior_tree__ Tree.new(unquote(root))
      case Tree.validate(@__jido_behavior_tree__) do
        :ok -> :ok
        {:error, reason} -> Config.compile_error!(__ENV__, Exception.message(reason))
      end

      unquote(registration)
      @spec unquote(name)() :: Tree.t()
      def unquote(name)(), do: @__jido_behavior_tree__
      Module.delete_attribute(__MODULE__, :__jido_behavior_tree__)
    end
  end

  defp children(body, path, caller) do
    statements =
      case body do
        {:__block__, _, statements} -> statements
        nil -> []
        statement -> [statement]
      end

    {nodes, _names} =
      Enum.map_reduce(statements, MapSet.new(), fn
        {kind, meta, [name | args]}, names when is_atom(kind) and is_list(args) ->
          caller = %{caller | line: Keyword.get(meta, :line, caller.line)}

          unless valid_name?(name) do
            Config.compile_error!(caller, "expected a literal atom node name")
          end

          if MapSet.member?(names, name) do
            Config.compile_error!(caller, "duplicate sibling node #{inspect(name)}")
          end

          path = path ++ [name]
          {node, declarations} = compile_node(kind, args, path, caller)
          named = quote do: Named.new(unquote(node), unquote(path))
          {{named, declarations}, MapSet.put(names, name)}

        _, _names ->
          Config.compile_error!(caller, "expected a Behavior Tree node declaration")
      end)

    {Enum.map(nodes, &elem(&1, 0)), Enum.flat_map(nodes, &elem(&1, 1))}
  end

  defp compile_node(kind, [[do: body]], path, caller) when is_map_key(@branches, kind) do
    {nodes, declarations} = children(body, path, caller)

    if nodes == [] do
      Config.compile_error!(caller, "#{kind} requires at least one child node")
    end

    module = Map.fetch!(@branches, kind)
    {quote(do: unquote(module).new(unquote(nodes))), declarations}
  end

  defp compile_node(:condition, [value], _path, caller) do
    expression = Expression.parse!(value, caller)
    {quote(do: Condition.new(unquote(Macro.escape(expression)))), []}
  end

  defp compile_node(:wait, [[milliseconds: duration]], _path, _caller)
       when is_integer(duration) and duration >= 0 do
    {quote(do: Wait.new(unquote(duration))), []}
  end

  defp compile_node(:node, [node], _path, _caller), do: {node, []}

  defp compile_node(:action, [binding, options, [do: body]], path, caller) do
    options!(options, [:inline], caller)
    inline_action(binding, Keyword.get(options, :inline, []), body, path, caller)
  end

  defp compile_node(:action, [target, options], path, caller) do
    options!(options, [:params, :inline, :do], caller)

    case Keyword.fetch(options, :do) do
      {:ok, body} ->
        options!(options, [:inline, :do], caller)
        inline_action(target, Keyword.get(options, :inline, []), body, path, caller)

      :error ->
        options!(options, [:params], caller)
        params = Expression.parse!(Keyword.get(options, :params, {:%{}, [], []}), caller)
        {action(target, params), []}
    end
  end

  defp compile_node(:action, [target], path, caller), do: compile_node(:action, [target, []], path, caller)

  defp compile_node(kind, _args, _path, caller),
    do: Config.compile_error!(caller, "invalid Behavior Tree node declaration #{kind}")

  defp inline_action(binding, options, body, path, caller) do
    options!(options, @inline_fields, caller)
    parsed = Inline.parse_bound!(binding, Keyword.put(options, :do, body), caller)
    params = Expression.parse!(parsed.params_ast, caller)
    [tree_name | node_path] = path
    identity = [host: __MODULE__, tree: tree_name] ++ Enum.map(node_path, &{:node, &1}) ++ [role: :action]

    %{declaration_ast: declaration, target_ast: target} =
      Inline.compile!(Macro.escape(identity), parsed, caller, default_name: Atom.to_string(List.last(path)))

    {action(target, params), [declaration]}
  end

  defp action(target, params), do: quote(do: Action.new(unquote(target), unquote(Macro.escape(params))))

  defp options!(options, keys, caller) do
    Config.validate_options!(options, caller, "expected a keyword list", "Behavior Tree option", keys)
  end

  defp valid_name?(name), do: is_atom(name) and name not in [nil, false, true]
end
