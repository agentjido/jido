defmodule Jido.Action.Inline.Parser do
  @moduledoc false

  alias Jido.Action.Inline
  alias Jido.Authoring.Options

  @doc false
  @spec bound!(Macro.t(), keyword(), Macro.Env.t()) :: Inline.t()
  def bound!(bindings, options, caller) do
    bindings = if is_list(bindings), do: bindings, else: [bindings]

    if List.improper?(bindings),
      do: error!(nil, caller, "inline Action bindings must be a proper list")

    parsed =
      Enum.map(bindings, fn
        {:<-, _, [pattern, source]} -> {binding_kind!(pattern, caller), pattern, source}
        other -> error!(other, caller, "expected a binding in the form name <- source")
      end)

    {params, pattern} = params_and_pattern!(parsed, caller)
    build!(:bound, params, pattern, options, caller)
  end

  @doc false
  @spec callback!(Macro.t() | nil, keyword(), Macro.Env.t()) :: Inline.t()
  def callback!(pattern, options, caller) do
    build!(:callback, nil, pattern, options, caller)
  end

  defp build!(mode, params, pattern, options, caller) do
    options!(options, [:do, :name, :description, :schema, :output_schema, :context], caller)

    body =
      case Keyword.fetch(options, :do) do
        {:ok, body} -> body
        :error -> error!(nil, caller, "inline Action requires a do block")
      end

    clauses = classify_body!(body, caller)

    cond do
      clauses && mode == :callback && not is_nil(pattern) ->
        error!(
          pattern,
          caller,
          "inline Action clause body cannot include a header pattern"
        )

      is_nil(clauses) && mode == :callback ->
        binding_kind!(
          pattern,
          caller,
          "inline Action callback requires a named variable or a map pattern"
        )

      true ->
        :ok
    end

    patterns = if clauses, do: Enum.map(clauses, &elem(&1, 0)), else: List.wrap(pattern)
    context = context_from_options!(options, patterns, caller)

    %Inline{
      mode: mode,
      params_ast: params,
      pattern_ast: if(clauses && mode == :callback, do: nil, else: pattern),
      body_ast: body,
      clauses: clauses,
      options: Keyword.drop(options, [:do, :context]),
      context_ast: context
    }
  end

  @doc false
  @spec options!(term(), [atom()], Macro.Env.t(), String.t()) :: :ok
  def options!(options, supported, caller, kind \\ "option") do
    Options.validate!(
      options,
      source_env(options, caller),
      "inline Action #{kind}s must be a keyword list",
      "inline Action #{kind}",
      supported
    )
  end

  defp context_from_options!(options, patterns, caller) do
    case Keyword.fetch(options, :context) do
      :error -> nil
      {:ok, context} -> context!(context, patterns, caller)
    end
  end

  defp context!({name, _, context} = variable, patterns, caller)
       when is_atom(name) and name != :_ and is_atom(context) do
    names =
      Enum.reduce(patterns, MapSet.new(), fn pattern, acc ->
        {_ast, names} =
          Macro.prewalk(pattern || {:__block__, [], []}, acc, fn
            {var, _, ctx} = node, names when is_atom(var) and is_atom(ctx) ->
              {node, MapSet.put(names, var)}

            node, names ->
              {node, names}
          end)

        names
      end)

    if MapSet.member?(names, name) do
      error!(
        variable,
        caller,
        "inline Action context variable collides with a parameter variable: #{name}"
      )
    end

    variable
  end

  defp context!(other, _patterns, caller),
    do: error!(other, caller, "inline Action context must be a named variable")

  defp binding_kind!(
         pattern,
         caller,
         message \\ "inline Action requires a named variable or a sole map pattern"
       )

  defp binding_kind!({:_, _, context} = pattern, caller, _message) when is_atom(context),
    do: error!(pattern, caller, "a bare _ binding is not supported; use a named variable or []")

  defp binding_kind!({name, _, context}, _caller, _message)
       when is_atom(name) and is_atom(context),
       do: {:named, name}

  defp binding_kind!({:%{}, _, _} = pattern, caller, _message) do
    validate_pattern!(pattern, caller)
    :map
  end

  defp binding_kind!({:%, _, _} = pattern, caller, _message),
    do:
      error!(
        pattern,
        caller,
        "top-level struct patterns are not supported in inline Action bindings"
      )

  defp binding_kind!({operator, _, _} = pattern, caller, _message) when operator in [:^, :when],
    do: validate_pattern!(pattern, caller)

  defp binding_kind!(pattern, caller, message), do: error!(pattern, caller, message)

  defp params_and_pattern!([{:map, pattern, source}], _caller), do: {source, pattern}

  defp params_and_pattern!(bindings, caller) do
    if Enum.any?(bindings, &match?({:map, _, _}, &1)) do
      error!(nil, caller, "a map pattern must be the only inline Action binding")
    end

    {params, patterns, _names} =
      Enum.reduce(bindings, {[], [], MapSet.new()}, fn {{:named, name}, pattern, source},
                                                       {params, patterns, names} ->
        if MapSet.member?(names, name) do
          error!(pattern, caller, "duplicate inline Action binding: #{inspect(name)}")
        end

        {[{name, source} | params], [{name, pattern} | patterns], MapSet.put(names, name)}
      end)

    {{:%{}, [line: caller.line], Enum.reverse(params)},
     {:%{}, [line: caller.line], Enum.reverse(patterns)}}
  end

  defp classify_body!(body, caller) do
    case clause_asts(body) do
      {:ok, asts} ->
        Enum.map(asts, &parse_clause!(&1, caller))

      :mixed ->
        error!(body, caller, "inline Action cannot mix clause heads with an expression body")

      :expression ->
        nil
    end
  end

  defp clause_asts({:->, _, _} = clause), do: {:ok, [clause]}

  defp clause_asts([{:->, _, _} | _] = expressions) do
    if Enum.all?(expressions, &match?({:->, _, _}, &1)),
      do: {:ok, expressions},
      else: :mixed
  end

  defp clause_asts({:__block__, _, expressions}) when expressions != [] do
    clauses? = Enum.map(expressions, &match?({:->, _, _}, &1))

    cond do
      Enum.all?(clauses?) -> {:ok, expressions}
      Enum.any?(clauses?) -> :mixed
      true -> :expression
    end
  end

  defp clause_asts(_), do: :expression

  defp parse_clause!({:->, meta, [left, body]}, caller) do
    caller = with_line(caller, meta)
    {pattern, guard} = clause_head!(left, caller)
    validate_clause_pattern!(pattern, caller)
    {pattern, guard, body}
  end

  defp clause_head!([{:when, _meta, [pattern, guard]}], _caller), do: {pattern, guard}

  defp clause_head!([{:when, _meta, _args} = head], caller),
    do: clause_head_error!(head, caller)

  defp clause_head!([pattern], _caller), do: {pattern, nil}

  defp clause_head!(other, caller) do
    clause_head_error!(clause_head_node(other), caller)
  end

  @spec clause_head_error!(term(), Macro.Env.t()) :: no_return()
  defp clause_head_error!(head, caller),
    do: error!(head, caller, "inline Action clause requires one parameter pattern")

  defp clause_head_node([node | _]), do: node
  defp clause_head_node(other), do: other

  defp validate_clause_pattern!({:_, _, context}, _caller) when is_atom(context), do: :ok

  defp validate_clause_pattern!({name, _, context}, _caller)
       when is_atom(name) and is_atom(context),
       do: :ok

  defp validate_clause_pattern!({:%{}, _, _} = pattern, caller) do
    validate_pattern!(pattern, caller)
    :ok
  end

  defp validate_clause_pattern!({:%, _, _} = pattern, caller),
    do:
      error!(
        pattern,
        caller,
        "top-level struct patterns are not supported in inline Action clauses"
      )

  defp validate_clause_pattern!(pattern, caller),
    do:
      error!(
        pattern,
        caller,
        "inline Action clause requires a named variable, `_`, or a map pattern"
      )

  # Normal Elixir compilation checks the remaining pattern syntax in the owner.
  defp validate_pattern!(pattern, caller) do
    Macro.prewalk(pattern, fn
      {:^, _, _} = node ->
        error!(node, caller, "pinned variables are not supported in inline Action bindings")

      {:when, _, _} = node ->
        error!(node, caller, "guards are not supported in inline Action bindings")

      {:%{}, _, pairs} = node ->
        validate_map_keys!(pairs, node, caller)
        node

      node ->
        node
    end)
  end

  defp validate_map_keys!(pairs, pattern, caller) do
    Enum.reduce(pairs, MapSet.new(), fn
      {key, _}, seen ->
        normalized = Macro.postwalk(key, &normalize_literal/1)

        unless Macro.quoted_literal?(normalized),
          do: error!(key, caller, "inline Action map pattern keys must be literals")

        if MapSet.member?(seen, normalized),
          do: error!(pattern, caller, "duplicate inline Action map key: #{Macro.to_string(key)}")

        MapSet.put(seen, normalized)

      _, _ ->
        error!(pattern, caller, "map updates are not supported in inline Action patterns")
    end)
  end

  defp normalize_literal({:-, _, [number]}) when is_number(number), do: -number
  defp normalize_literal({:+, _, [number]}) when is_number(number), do: number
  defp normalize_literal({form, metadata, args}) when is_list(metadata), do: {form, [], args}
  defp normalize_literal(value), do: value

  defp with_line(caller, meta) when is_list(meta),
    do: %{caller | line: Keyword.get(meta, :line, caller.line)}

  defp with_line(caller, _meta), do: caller

  @doc false
  @spec error!(term(), Macro.Env.t(), String.t()) :: no_return()
  def error!(value, caller, description),
    do: Options.error!(source_env(value, caller), description)

  defp source_env({_form, metadata, _args}, caller) when is_list(metadata),
    do: with_line(caller, metadata)

  defp source_env(_value, caller), do: caller
end
