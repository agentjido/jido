defmodule Jido.Agent.DSL.Macros do
  @moduledoc false

  alias Jido.Action.Inline

  @entity Jido.Agent.DSL.Extension.Routes.Route
  defmacro route(path, target_or_options) do
    if Keyword.keyword?(target_or_options) do
      build(path, nil, target_or_options, __CALLER__)
    else
      build(path, target_or_options, [], __CALLER__)
    end
  end

  defmacro route(path, target_or_options, options) do
    if Keyword.keyword?(target_or_options) do
      build(path, nil, target_or_options ++ options, __CALLER__)
    else
      build(path, target_or_options, options, __CALLER__)
    end
  end

  @doc false
  def default_name(path), do: path

  defp build(path, target, options, caller) do
    validate_options!(options, caller)
    {block, route_options} = Keyword.pop(options, :do)
    {inline, route_block} = extract_inline(block, caller)

    cond do
      inline && not is_nil(target) ->
        error!(caller, "route cannot combine a target module with an inline Action")

      inline ->
        build_inline(path, inline, route_options, route_block, caller)

      is_nil(target) ->
        error!(caller, "route requires a target module or one inline Action")

      true ->
        call_entity(path, target, route_options, route_block, caller)
    end
  end

  defp build_inline(path, {metadata, args}, route_options, route_block, caller) do
    caller = %{caller | line: Keyword.get(metadata, :line, caller.line)}
    parsed = parse_inline!(args, caller)
    route_path = Macro.unique_var(:route_path, __MODULE__)

    identity =
      quote do: [host: Jido.Agent, route: unquote(route_path), role: :action]

    compiled =
      Inline.compile!(identity, parsed, caller,
        default_name: quote(do: unquote(__MODULE__).default_name(unquote(route_path))),
        remove_imports: [{__MODULE__, [route: 2, route: 3]}]
      )

    declaration =
      call_entity(route_path, compiled.target_ast, route_options, route_block, caller)

    quote line: caller.line do
      unquote(route_path) = unquote(path)
      unquote(compiled.declaration_ast)
      unquote(declaration)
    end
  end

  defp parse_inline!([pattern, options], caller) when is_list(options) do
    Inline.parse_callback!(pattern, options, caller)
  end

  defp parse_inline!([pattern, options, body], caller)
       when is_list(options) and is_list(body) do
    Inline.parse_callback!(pattern, options ++ body, caller)
  end

  defp parse_inline!(_args, caller) do
    error!(caller, "inline route Action has an invalid declaration")
  end

  defp extract_inline(nil, _caller), do: {nil, nil}

  defp extract_inline(block, caller) do
    expressions =
      case block do
        {:__block__, _, expressions} -> expressions
        expression -> [expression]
      end

    {actions, remaining} =
      Enum.split_with(expressions, fn
        {:action, _, _} -> true
        _ -> false
      end)

    case actions do
      [] ->
        {nil, block}

      [{:action, metadata, args}] ->
        remaining =
          case remaining do
            [] -> nil
            [expression] -> expression
            expressions -> {:__block__, [], expressions}
          end

        {{metadata, args}, remaining}

      _ ->
        error!(caller, "route accepts only one inline Action")
    end
  end

  defp call_entity(path, target, route_options, block, caller) do
    options = if is_nil(block), do: route_options, else: Keyword.put(route_options, :do, block)

    quote generated: true, line: caller.line, file: caller.file do
      require unquote(@entity)
      unquote(@entity).__route__(unquote(path), unquote(target), unquote(options))
    end
  end

  defp validate_options!(options, caller) do
    unless Keyword.keyword?(options) do
      error!(caller, "route options must be a keyword list")
    end

    keys = Keyword.keys(options)
    if length(keys) != length(Enum.uniq(keys)), do: error!(caller, "duplicate route option")
  end

  defp error!(caller, description) do
    raise CompileError, file: caller.file, line: caller.line, description: description
  end
end
