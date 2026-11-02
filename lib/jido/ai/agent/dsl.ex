defmodule Jido.AI.Agent.DSL do
  @moduledoc false

  @entity Module.concat([
            Jido.AI.Agent.Plugin,
            Macro.camelize("__ai__"),
            Macro.camelize("__reasoning__")
          ])
  @tools_section Module.concat([
                   Jido.AI.Agent.Plugin,
                   Macro.camelize("__tools__")
                 ])

  defmacro ai(do: block) do
    caller = __CALLER__
    declarations = expressions(block)
    reasoning = Enum.filter(declarations, &match?({:reasoning, _, _}, &1))
    tools = Enum.filter(declarations, &match?({:tools, _, _}, &1))

    if Module.get_attribute(caller.module, :jido_ai_block_declared) do
      compile_error!(caller, caller.line, "An Agent can define only one ai block")
    end

    if length(reasoning) != 1 do
      compile_error!(caller, caller.line, "ai requires exactly one reasoning declaration")
    end

    if length(tools) > 1 do
      compile_error!(caller, caller.line, "An Agent can define at most one tools block")
    end

    if length(reasoning) + length(tools) != length(declarations) do
      compile_error!(caller, caller.line, "ai accepts only reasoning and tools declarations")
    end

    Module.put_attribute(caller.module, :jido_ai_block_declared, true)

    quote do
      __ai__(do: unquote(block))
    end
  end

  defmacro tools(do: block) do
    caller = __CALLER__

    unless Enum.all?(expressions(block), &tool_declaration?/1) do
      compile_error!(caller, caller.line, "tools accepts only action or flow declarations")
    end

    quote do
      require unquote(@tools_section)
      unquote(@tools_section).__tools__(do: unquote(block))
    end
  end

  defmacro reasoning(do: body), do: inline_reasoning(body, __CALLER__)

  defmacro reasoning(target), do: referenced_reasoning(target, nil, __CALLER__)

  defmacro reasoning(target, do: body), do: referenced_reasoning(target, body, __CALLER__)

  defp tool_declaration?({kind, _meta, [_target]}) when kind in [:action, :flow], do: true
  defp tool_declaration?(_declaration), do: false

  defp referenced_reasoning(target_ast, body, caller) do
    target =
      executable!(
        target_ast,
        :flow,
        "reasoning must reference a compiled Jido Flow module",
        caller
      )

    defaults = if is_nil(body), do: %{}, else: parse_defaults!(body, target, caller)

    quote line: caller.line do
      require unquote(@entity)
      unquote(@entity).__reasoning__(unquote(target), defaults: unquote(Macro.escape(defaults)))
    end
  end

  defp inline_reasoning(body, caller) do
    identity = quote do: [host: Jido.Agent, route: "jido.ai.request", role: :flow]

    compiled =
      Jido.Flow.Inline.compile!(
        identity,
        quote do
          [
            name: "reasoning",
            output_schema: Zoi.object(%{state: Zoi.map(), response: Zoi.map()})
          ]
        end,
        body,
        caller
      )

    quote line: caller.line do
      unquote(compiled.declaration_ast)
      require unquote(@entity)
      unquote(@entity).__reasoning__(unquote(compiled.target_ast), defaults: %{})
    end
  end

  defp parse_defaults!(body, target, caller) do
    defaults = block!(body, "reasoning", caller)

    case Jido.Flow.normalize_defaults(defaults, target) do
      {:ok, defaults} ->
        if Map.has_key?(defaults, :input) do
          compile_error!(caller, caller.line, "reasoning input cannot be a default")
        else
          defaults
        end

      {:error, error} ->
        path = error.details |> Map.get(:path, []) |> Enum.map_join(".", &to_string/1)
        suffix = if path == "", do: "", else: " at #{path}"

        compile_error!(
          caller,
          caller.line,
          "reasoning configuration is invalid for #{inspect(target)}#{suffix}: #{Exception.message(error)}"
        )
    end
  end

  defp block!(body, scope, caller) do
    body
    |> expressions()
    |> Enum.reduce({%{}, MapSet.new()}, fn declaration, {config, names} ->
      {name, value, line} = declaration!(declaration, scope, caller)

      if MapSet.member?(names, name) do
        compile_error!(caller, line, "#{scope} defines #{name} more than once")
      end

      {Map.put(config, name, value), MapSet.put(names, name)}
    end)
    |> elem(0)
  end

  defp declaration!({name, metadata, [[do: body]]}, scope, caller) when is_atom(name) do
    {name, block!(body, "#{scope}.#{name}", caller), metadata[:line]}
  end

  defp declaration!({name, metadata, [value_ast]}, _scope, caller) when is_atom(name) do
    {name, literal!(name, value_ast, metadata[:line], caller), metadata[:line]}
  end

  defp declaration!(declaration, scope, caller) do
    compile_error!(
      caller,
      expression_line(declaration, caller.line),
      "#{scope} accepts only named literal values and nested blocks"
    )
  end

  defp literal!(name, value_ast, line, caller) do
    if Macro.quoted_literal?(value_ast) do
      {value, []} = Code.eval_quoted(value_ast, [], caller)
      value
    else
      compile_error!(caller, line, "#{name} requires a compile-time literal value")
    end
  end

  defp executable!(target_ast, kind, message, caller) do
    target = Macro.expand(target_ast, caller)

    with true <- is_atom(target) and target not in [nil, true, false],
         {:module, ^target} <- Code.ensure_compiled(target),
         {:ok, %{kind: ^kind}} <- Jido.Instruction.resolve(target) do
      target
    else
      _reason -> compile_error!(caller, caller.line, message)
    end
  end

  defp expressions({:__block__, _metadata, expressions}), do: expressions
  defp expressions(nil), do: []
  defp expressions(expression), do: [expression]

  defp expression_line({_name, metadata, _arguments}, fallback) when is_list(metadata),
    do: Keyword.get(metadata, :line, fallback)

  defp expression_line(_expression, fallback), do: fallback

  defp compile_error!(caller, line, description) do
    raise CompileError,
      file: caller.file,
      line: line || caller.line,
      description: description
  end
end
