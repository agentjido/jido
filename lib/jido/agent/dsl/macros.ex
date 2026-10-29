defmodule Jido.Agent.DSL.Macros do
  @moduledoc false
  defmacro agent(name), do: quote(do: %{kind: :agent, name: unquote(name)})
  defmacro parent, do: quote(do: %{kind: :parent})
  defmacro state(do: block), do: section(:state, :__state__, block, __CALLER__)
  defmacro routes(do: block), do: section(:routes, :__routes__, block, __CALLER__)
  defmacro topology(do: block), do: section(:topology, :__topology__, block, __CALLER__)

  defp section(name, internal, block, caller) do
    declared = Module.get_attribute(caller.module, :agent_sections) || []

    if name in declared,
      do: error!(caller, "Agent section #{name} can be declared only once")

    Module.put_attribute(caller.module, :agent_sections, [name | declared])

    settings =
      case name do
        :state -> [:schema, :initial_state]
        :routes -> [:signal_source]
        _ -> []
      end

    keys = for {key, _, _} <- expressions(block), key in settings, do: key

    if Enum.uniq(keys) != keys,
      do: error!(caller, "Agent field can be declared only once")

    quote do
      unquote(internal)(do: unquote(block))
    end
  end

  def expressions({:__block__, _, items}), do: items
  def expressions(item), do: [item]

  defp error!(caller, message),
    do: raise(CompileError, file: caller.file, line: caller.line, description: message)
end

defmodule Jido.Agent.DSL.RouteMacros do
  @moduledoc false
  alias Jido.Action.Inline, as: InlineAction
  alias Jido.Flow.Inline, as: InlineFlow

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

    unknown = Keyword.keys(options) -- [:as, :defaults, :do]
    if unknown != [], do: error!(caller, "Unknown route options: #{inspect(unknown)}")
    {body, options} = Keyword.pop(options, :do)
    {declaration, handler, state, reply} = route_body(path, target, body, caller)
    options = options ++ [state: Macro.escape(state), reply: Macro.escape(reply)]

    quote line: caller.line do
      unquote(declaration)
      require unquote(@entity)
      unquote(@entity).__route__(unquote(path), unquote(handler), unquote(options))
    end
  end

  defp route_body(_path, nil, nil, caller),
    do: error!(caller, "A route requires exactly one handler in its body")

  defp route_body(_path, target, nil, _caller),
    do: {nil, quote(do: %{kind: :executable, target: unquote(target)}), default_state(), nil}

  defp route_body(path, target, body, caller) do
    roles = Enum.group_by(Jido.Agent.DSL.Macros.expressions(body), &role/1)

    if Map.has_key?(roles, :unknown),
      do: error!(caller, "A route body contains an unsupported declaration")

    handlers = Map.get(roles, :handler, [])
    mappings = Map.get(roles, :mapping, [])

    case target do
      nil -> inline_route_body(path, handlers, mappings, caller)
      target -> referenced_route_body(target, handlers, mappings, caller)
    end
  end

  defp role({name, _, _}) when name in [:action, :flow, :forward, :transform], do: :handler
  defp role({name, _, _}) when name in [:state, :reply], do: :mapping
  defp role(_expression), do: :unknown

  defp referenced_route_body(target, [], mappings, caller) do
    {state, reply} = executable_mappings(mappings, caller)
    {nil, quote(do: %{kind: :executable, target: unquote(target)}), state, reply}
  end

  defp referenced_route_body(_target, _handlers, _mappings, caller),
    do: error!(caller, "A positional target route body can contain only state and reply")

  defp inline_route_body(_path, handlers, _mappings, caller) when length(handlers) != 1,
    do: error!(caller, "A route without a positional target requires exactly one handler")

  defp inline_route_body(path, [{kind, meta, args}], mappings, caller) do
    caller = %{caller | line: Keyword.get(meta, :line, caller.line)}
    terminal? = kind in [:forward, :transform]
    if terminal?, do: terminal_mappings!(mappings, caller)

    {declaration, handler} =
      case kind do
        :action -> inline_action(path, args, caller)
        :flow -> inline_flow(path, args, caller)
        :transform -> transform(path, args, caller)
        :forward -> {nil, forward_handler(args, caller)}
      end

    {state, reply} =
      if terminal?, do: {:unchanged, nil}, else: executable_mappings(mappings, caller)

    {declaration, handler, state, reply}
  end

  defp executable_mappings(mappings, caller) do
    states = for {:state, _, _} = state <- mappings, do: state
    replies = for {:reply, _, _} = reply <- mappings, do: reply

    if length(states) > 1,
      do: error!(caller, "An Action or Flow route accepts at most one state declaration")

    if length(replies) > 1,
      do: error!(caller, "An Action or Flow route accepts at most one reply declaration")

    state = if states == [], do: default_state(), else: parse_state(hd(states), caller)
    {state, parse_reply(List.first(replies), caller)}
  end

  defp default_state, do: %{source: :output, path: []}

  defp terminal_mappings!([], _caller), do: :ok

  defp terminal_mappings!(_mappings, caller),
    do: error!(caller, "A forward or transform route body can contain only its handler")

  defp parse_state({:state, _meta, [:unchanged]}, _caller), do: :unchanged

  defp parse_state({:state, _meta, [[from: selector]]}, caller),
    do: parse_selector(selector, caller)

  defp parse_state(_state, caller),
    do: error!(caller, "State must be :unchanged or select from output")

  defp parse_reply(nil, _caller), do: nil

  defp parse_reply({:reply, _meta, [type, [from: selector]]}, caller) when is_binary(type) do
    %{type: type, from: parse_selector(selector, caller)}
  end

  defp parse_reply(_reply, caller),
    do: error!(caller, "Reply requires one literal Signal type and one output selector")

  defp parse_selector({:output, _meta, []}, _caller), do: %{source: :output, path: []}

  defp parse_selector({:output, _meta, [path]}, caller) do
    path = if is_list(path), do: path, else: [path]

    if Enum.all?(path, &(is_atom(&1) or is_binary(&1))),
      do: %{source: :output, path: path},
      else: error!(caller, "Output selector paths contain only literal atom or string fields")
  end

  defp parse_selector(_selector, caller),
    do: error!(caller, "Result mappings require output() or output(path)")

  defp forward_handler([[to: target]], _caller),
    do: quote(do: %{kind: :forward, target: unquote(target)})

  defp forward_handler(_args, caller),
    do: error!(caller, "Forward requires only one explicit :to destination")

  defp inline_action(path, args, caller) do
    {pattern, options} =
      case args do
        [opts] when is_list(opts) -> {nil, opts}
        [opts, body] when is_list(opts) and is_list(body) -> {nil, opts ++ body}
        [pattern, opts] when is_list(opts) -> {pattern, opts}
        [pattern, opts, body] when is_list(opts) and is_list(body) -> {pattern, opts ++ body}
        _ -> error!(caller, "Invalid inline Action")
      end

    parsed = InlineAction.parse_callback!(pattern, options, caller)
    identity = quote do: [host: Jido.Agent, route: unquote(path), role: :action]

    compiled =
      InlineAction.compile!(identity, parsed, caller,
        default_name: path,
        remove_imports: [
          {__MODULE__, [route: 1, route: 2, route: 3, route: 4]}
        ]
      )

    {compiled.declaration_ast, quote(do: %{kind: :action, target: unquote(compiled.target_ast)})}
  end

  defp inline_flow(path, args, caller) do
    {options, body} =
      case args do
        [options, [do: body]] when is_list(options) ->
          {options, body}

        [options] when is_list(options) ->
          case Keyword.pop(options, :do) do
            {nil, _options} -> error!(caller, "Inline Flow requires a body")
            {body, options} -> {options, body}
          end

        _other ->
          error!(caller, "Invalid inline Flow")
      end

    unless Keyword.keyword?(options) and Enum.uniq(Keyword.keys(options)) == Keyword.keys(options),
      do: error!(caller, "Inline Flow requires unique keyword options")

    options = Keyword.put_new(options, :name, path)
    identity = quote do: [host: Jido.Agent, route: unquote(path), role: :flow]
    compiled = InlineFlow.compile!(identity, options, body, caller)

    {compiled.declaration_ast, quote(do: %{kind: :flow, target: unquote(compiled.target_ast)})}
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

  defp transform_clause(fun, pattern, body, line) do
    head =
      case pattern do
        {:when, meta, [pattern, guard]} -> {:when, meta, [{fun, meta, [pattern]}, guard]}
        pattern -> {fun, [line: line, context: Elixir], [pattern]}
      end

    quote line: line do
      defp unquote(head), do: unquote(body)
    end
  end

  defp error!(caller, message),
    do: raise(CompileError, file: caller.file, line: caller.line, description: message)
end
