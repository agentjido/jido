defmodule Jido.Agent.DSL.Macros do
  @moduledoc false
  defmacro agent(do: block), do: section(:agent, :__agent__, block, __CALLER__)
  defmacro routes(do: block), do: section(:routes, :__routes__, block, __CALLER__)
  defmacro topology(do: block), do: section(:topology, :__topology__, block, __CALLER__)

  defp section(name, internal, block, caller) do
    attr = :agent_sections
    declared = Module.get_attribute(caller.module, attr) || []

    if name in declared,
      do:
        raise(CompileError,
          file: caller.file,
          line: caller.line,
          description: "Agent section #{name} can be declared only once"
        )

    Module.put_attribute(caller.module, attr, [name | declared])

    settings =
      case name do
        :agent -> [:schema, :metadata]
        :routes -> [:signal_source]
        _ -> []
      end

    expressions =
      case block do
        {:__block__, _, items} -> items
        item -> [item]
      end

    keys = for {key, _, _} <- expressions, key in settings, do: key

    if Enum.uniq(keys) != keys,
      do:
        raise(CompileError,
          file: caller.file,
          line: caller.line,
          description: "Agent field can be declared only once"
        )

    quote do
      unquote(internal)(do: unquote(block))
    end
  end
end

defmodule Jido.Agent.DSL.RouteMacros do
  @moduledoc false
  alias Jido.Action.Inline

  @entity Module.concat([
            Jido.Agent.DSL.Extension,
            Macro.camelize("__routes__"),
            Macro.camelize("__route__")
          ])

  defmacro route(path), do: build(path, nil, [], __CALLER__)

  defmacro route(path, target_or_options, options \\ []) do
    if Keyword.keyword?(target_or_options),
      do: build(path, nil, target_or_options ++ options, __CALLER__),
      else: build(path, target_or_options, options, __CALLER__)
  end

  defmacro route(path, target, options, block),
    do: build(path, target, options ++ block, __CALLER__)

  defp build(path, target, options, caller) do
    unless Keyword.keyword?(options) and Enum.uniq(Keyword.keys(options)) == Keyword.keys(options),
      do: error!(caller, "Route requires unique keyword options")

    unknown = Keyword.keys(options) -- [:as, :defaults, :emits, :do, :via]
    if unknown != [], do: error!(caller, "Unknown route options: #{inspect(unknown)}")
    {path, target, options} = signal_action_route(path, target, options, caller)
    {body, options} = Keyword.pop(options, :do)
    {declaration, handler} = handler(path, target, body, caller)

    quote line: caller.line do
      unquote(declaration)
      require unquote(@entity)
      unquote(@entity).__route__(unquote(path), unquote(handler), unquote(options))
    end
  end

  defp signal_action_route(path, target, options, caller) do
    case Macro.expand(path, caller) do
      module when is_atom(module) and module not in [nil, true, false] ->
        if target != nil or Keyword.has_key?(options, :do),
          do: error!(caller, "A SignalAction route accepts :via instead of a target or block")

        {via, options} = Keyword.pop(options, :via, path)

        if via in [nil, true, false],
          do: error!(caller, ":via requires an Action or Flow module")

        type = quote do: Jido.SignalAction.route_type!(unquote(path), __ENV__)
        {type, via, options}

      _ ->
        if Keyword.has_key?(options, :via),
          do: error!(caller, ":via requires a SignalAction module route")

        {path, target, options}
    end
  end

  defp handler(_path, nil, nil, _caller), do: {nil, quote(do: %{kind: :pass_through})}

  defp handler(_path, target, nil, _caller) do
    {nil, quote(do: %{kind: :executable, target: unquote(target)})}
  end

  defp handler(_path, target, _body, caller) when not is_nil(target),
    do: error!(caller, "A route cannot combine a target and an inline handler")

  defp handler(path, nil, body, caller) do
    expressions =
      case body do
        {:__block__, _, items} -> items
        item -> [item]
      end

    case expressions do
      [{:action, meta, args}] ->
        inline(path, args, %{caller | line: Keyword.get(meta, :line, caller.line)})

      [{:transform, meta, args}] ->
        transform(path, args, %{caller | line: Keyword.get(meta, :line, caller.line)})

      _ ->
        error!(caller, "A route block requires exactly one action or transform")
    end
  end

  defp inline(path, args, caller) do
    parsed =
      case args do
        [opts] when is_list(opts) ->
          Inline.parse_callback!(nil, opts, caller)

        [opts, body] when is_list(opts) and is_list(body) ->
          Inline.parse_callback!(nil, opts ++ body, caller)

        [pattern, opts] when is_list(opts) ->
          Inline.parse_callback!(pattern, opts, caller)

        [pattern, opts, body] when is_list(opts) and is_list(body) ->
          Inline.parse_callback!(pattern, opts ++ body, caller)

        _ ->
          error!(caller, "Invalid inline Action")
      end

    identity = quote do: [host: Jido.Agent, route: unquote(path), role: :action]

    compiled =
      Inline.compile!(identity, parsed, caller,
        default_name: path,
        remove_imports: [{__MODULE__, [route: 1, route: 2, route: 3, route: 4]}]
      )

    {compiled.declaration_ast, quote(do: %{kind: :action, target: unquote(compiled.target_ast)})}
  end

  defp transform(path, args, caller) do
    {pattern, body} =
      case args do
        [[do: body]] -> {nil, body}
        [pattern, [do: body]] -> {pattern, body}
        _ -> error!(caller, "Transform requires one argument or ordinary clauses")
      end

    path_var = Macro.unique_var(:transform_path, __MODULE__)
    fun_var = Macro.unique_var(:transform_fun, __MODULE__)
    private_var = Macro.unique_var(:transform_private, __MODULE__)
    fun = {:unquote, [], [fun_var]}
    private = {:unquote, [], [private_var]}
    bound_path = {:unquote, [], [path_var]}

    clauses =
      case {pattern, body} do
        {nil, [{:->, _, _} | _] = clauses} ->
          Enum.map(clauses, fn
            {:->, meta, [[head], body]} ->
              transform_clause(private, head, body, Keyword.get(meta, :line, caller.line))

            _ ->
              error!(caller, "Transform clauses must each have one argument")
          end)

        {nil, _} ->
          error!(caller, "A transform without an argument requires clauses")

        {pattern, body} ->
          [transform_clause(private, pattern, body, caller.line)]
      end

    declaration =
      quote line: caller.line do
        unquote(path_var) = unquote(path)

        {unquote(fun_var), unquote(private_var)} =
          Jido.Agent.DSL.RouteMacros.transform_names!(unquote(path_var))

        unquote_splicing(clauses)
        @doc false
        def unquote(fun)(%Jido.Signal{} = signal) do
          try do
            unquote(private)(signal)
          rescue
            error in FunctionClauseError ->
              if error.module == __MODULE__ and error.function == unquote(private) do
                Jido.Agent.Error.fail(
                  :transform_input,
                  [:routes, unquote(bound_path)],
                  "Signal does not match a transform clause"
                )
              else
                reraise error, __STACKTRACE__
              end
          end
        end
      end

    {declaration, quote(do: %{kind: :transform, target: {__MODULE__, unquote(fun_var), 1}})}
  end

  @doc false
  def transform_names!(path) do
    case Jido.Agent.Data.path(path) do
      :ok -> :ok
      {:error, error} -> raise error
    end

    suffix = :crypto.hash(:sha256, path) |> Base.encode16(case: :lower) |> binary_part(0, 16)

    {String.to_atom("__agent_transform_" <> suffix),
     String.to_atom("__agent_transform_clauses_" <> suffix)}
  end

  defp transform_clause(fun, {:when, meta, [pattern, guard]}, body, line) do
    head = {:when, meta, [{fun, meta, [pattern]}, guard]}

    quote line: line do
      defp unquote(head), do: unquote(body)
    end
  end

  defp transform_clause(fun, pattern, body, line) do
    quote line: line do
      defp unquote(fun)(unquote(pattern)), do: unquote(body)
    end
  end

  defp error!(caller, message),
    do: raise(CompileError, file: caller.file, line: caller.line, description: message)
end
