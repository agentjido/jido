defmodule Jido.Action.Inline.Compiler do
  @moduledoc false

  alias Jido.Action.Inline.{Owner, Parser}

  @doc false
  @spec compile!(Macro.t(), Jido.Action.Inline.t(), Macro.Env.t(), keyword()) ::
          Jido.Action.Inline.compilation()
  def compile!(path_ast, parsed, caller, options) do
    Owner.ensure_compiling!(caller)
    target = Macro.unique_var(:inline_action, __MODULE__)
    function = Macro.unique_var(:inline_function, __MODULE__)
    config = Keyword.put_new(parsed.options, :name, Keyword.get(options, :default_name))
    definition = owner_definition(function, parsed, caller, options)
    internal = Keyword.take(options, [:reserved_label, :module_label, :emit])

    declaration =
      quote line: caller.line do
        {unquote(target), unquote(function)} =
          unquote(__MODULE__).create!(
            unquote(path_ast),
            unquote(config),
            __ENV__,
            unquote(Macro.escape(internal))
          )

        unquote(definition)
      end

    %{target_ast: target, declaration_ast: declaration}
  end

  @doc false
  @spec create!(term(), keyword(), Macro.Env.t(), keyword()) :: {module(), atom()}
  def create!(path, config, caller, options) do
    Owner.setup!(caller)
    path = Owner.validate_path!(path, caller)
    Owner.check_identity!(path, caller)
    config = Jido.Authoring.Config.prepare!(:action, config, caller)

    {target, function} = identity(caller.module, path)

    Owner.reserve_function!(
      caller,
      {function, 2},
      Keyword.get(options, :reserved_label, "inline Action")
    )

    ensure_owner!(
      target,
      {caller.module, path},
      caller,
      Keyword.get(options, :module_label, "inline Action")
    )

    args = [target, function, path, config, caller]

    case Keyword.get(options, :emit) do
      nil -> apply(__MODULE__, :create_action!, args)
      {module, callback} -> apply(module, callback, [args])
    end

    Owner.register!(path, target, caller)
    {target, function}
  end

  defp identity(owner, path) do
    digest =
      :crypto.hash(:sha256, :erlang.term_to_binary({owner, path})) |> Base.encode16(case: :lower)

    target = Module.concat(Jido.Action.Generated.Inline, "A" <> digest)

    {target, target}
  end

  defp ensure_owner!(target, identity, caller, label) do
    if Code.ensure_loaded?(target) and
         not (function_exported?(target, :__jido_inline_action__, 0) and
                target.__jido_inline_action__() == identity) do
      Parser.error!(
        nil,
        caller,
        "generated #{label} module #{inspect(target)} already belongs to another definition"
      )
    end
  end

  @doc false
  @spec create_action!(module(), atom(), Jido.Action.Inline.path(), map(), Macro.Env.t()) ::
          tuple()
  def create_action!(target, function, path, config, caller) do
    owner = caller.module

    definition =
      quote generated: true do
        @moduledoc false
        @compile {:no_warn_undefined, unquote(owner)}
        use Jido.Authoring.Compiler,
          kind: :action,
          config: unquote(Macro.escape(config))

        @doc false
        @spec __jido_inline_action__() :: {module(), Jido.Action.Inline.path()}
        def __jido_inline_action__(), do: unquote(Macro.escape({owner, path}))

        @doc false
        @impl Jido.Action
        @spec run(map(), map()) :: Jido.Action.result()
        def run(params, context), do: unquote(owner).unquote(function)(params, context)
      end

    env = %{
      __ENV__
      | file: caller.file,
        line: caller.line,
        aliases: [],
        lexical_tracker: caller.lexical_tracker,
        tracers: caller.tracers
    }

    Module.create(target, definition, env)
  end

  defp owner_definition(function, parsed, caller, options) do
    unimports = declaration_unimports(Keyword.get(options, :remove_imports, []), caller)
    function_name = {:unquote, [], [function]}
    context = parsed.context_ast || Macro.var(:_context, __MODULE__)

    defs =
      case parsed.clauses do
        [_ | _] = clauses ->
          Enum.map(
            clauses,
            &clause_def(function_name, &1, context, unimports, caller.line)
          )

        _ ->
          [
            clause_def(
              function_name,
              {parsed.pattern_ast, nil, parsed.body_ast},
              context,
              unimports,
              caller.line
            )
          ]
      end

    quote line: caller.line do
      @doc false
      @__jido_inline_generated__ {unquote(function), 2}
      unquote_splicing(defs)
      Module.delete_attribute(__MODULE__, :__jido_inline_generated__)
    end
  end

  defp clause_def(function_name, {pattern, nil, body}, context, unimports, default_line) do
    quote line: ast_line(pattern, default_line) do
      @doc false
      @spec unquote(function_name)(map(), map()) :: Jido.Action.result()
      def unquote(function_name)(unquote(pattern), unquote(context)) do
        unquote_splicing(unimports)
        unquote(body)
      end
    end
  end

  defp clause_def(function_name, {pattern, guard, body}, context, unimports, default_line) do
    quote line: ast_line(pattern, default_line) do
      @doc false
      @spec unquote(function_name)(map(), map()) :: Jido.Action.result()
      def unquote(function_name)(unquote(pattern), unquote(context)) when unquote(guard) do
        unquote_splicing(unimports)
        unquote(body)
      end
    end
  end

  defp ast_line({_form, metadata, _args}, default) when is_list(metadata) do
    case Keyword.get(metadata, :line) do
      line when is_integer(line) and line > 0 -> line
      _ -> default
    end
  end

  defp ast_line(_ast, default), do: default

  defp declaration_unimports(removals, caller) do
    unless valid_removals?(removals) do
      Parser.error!(
        nil,
        caller,
        "inline Action remove_imports must be a list of {module, [{name, arity}]} entries"
      )
    end

    removals
    |> Enum.reduce([], fn {module, removed}, acc ->
      Keyword.update(acc, module, removed, &(&1 ++ removed))
    end)
    |> Enum.map(fn {module, removed} ->
      remaining =
        (Keyword.get(caller.functions, module, []) ++ Keyword.get(caller.macros, module, []))
        |> Enum.uniq()
        |> Enum.reject(&(&1 in removed))

      quote generated: true do
        import unquote(module), only: unquote(remaining)
      end
    end)
  end

  defp valid_removals?([]), do: true

  defp valid_removals?([{module, imports} | rest]) when is_atom(module) and not is_nil(module),
    do: valid_imports?(imports) and valid_removals?(rest)

  defp valid_removals?(_), do: false

  defp valid_imports?([]), do: true

  defp valid_imports?([{name, arity} | rest])
       when is_atom(name) and is_integer(arity) and arity >= 0,
       do: valid_imports?(rest)

  defp valid_imports?(_), do: false
end
