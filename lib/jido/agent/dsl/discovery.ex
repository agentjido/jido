defmodule Jido.Agent.DSL.Discovery do
  @moduledoc false

  # Spark must import provider sections at `use`. Read only literal provider
  # selections in the enclosing source module; no handler or section is evaluated.
  def options!(opts, caller) do
    {opts, _} = Code.eval_quoted(opts, [], caller)

    unless Keyword.keyword?(opts) and Enum.uniq(Keyword.keys(opts)) == Keyword.keys(opts),
      do: raise(ArgumentError, "Agent requires unique keyword options")

    plugins = plugins(caller)
    extensions = Keyword.get(opts, :extensions, [])

    case Jido.Agent.Extension.providers(extensions ++ plugins) do
      {:ok, _} -> :ok
      {:error, error} -> raise error
    end

    opts
    |> Keyword.put(:extensions, extensions ++ plugins)
    |> Keyword.put(:plugin_providers, plugins)
  end

  defp plugins(caller) do
    with {:ok, source} <- File.read(caller.file),
         {:ok, ast} <- Code.string_to_quoted(source, columns: true) do
      {_ast, found} =
        Macro.prewalk(ast, [], fn
          {:defmodule, _, [_name, [do: body]]} = node, acc ->
            if own_use?(body, caller),
              do: {node, collect(body, caller) ++ acc},
              else: {node, acc}

          node, acc ->
            {node, acc}
        end)

      found
    else
      _ -> []
    end
  end

  defp own_use?(body, caller) do
    expressions =
      case body do
        {:__block__, _, items} -> items
        item -> [item]
      end

    Enum.any?(expressions, fn
      {:use, meta, [module | _]} ->
        Keyword.get(meta, :line) == caller.line and Macro.expand(module, caller) == Jido.Agent

      _ ->
        false
    end)
  end

  defp collect(body, caller) do
    {_env, plugins} =
      Enum.reduce(expressions(body), {caller, []}, fn
        {:alias, _, [module | options]}, {env, plugins} ->
          aliases = alias_pairs(module, options, env)
          {%{env | aliases: aliases ++ env.aliases}, plugins}

        {:agent, _, [[do: body]]}, {env, plugins} ->
          {env, plugins ++ agent_plugins(body, env)}

        _, acc ->
          acc
      end)

    plugins
  end

  defp agent_plugins(body, env) do
    {_env, providers} =
      Enum.reduce(expressions(body), {env, []}, fn
        {:alias, _, [module | options]}, {env, providers} ->
          {%{env | aliases: alias_pairs(module, options, env) ++ env.aliases}, providers}

        {:plugin, _, [module | _]}, {env, providers} ->
          expanded = Macro.expand(module, env)

          unless is_atom(expanded),
            do: raise(ArgumentError, "Plugin provider must be a literal module alias")

          {env, providers ++ [expanded]}

        _, acc ->
          acc
      end)

    providers
  end

  defp expressions({:__block__, _, items}), do: items
  defp expressions(item), do: [item]

  defp alias_pairs({{:., _, [base, :{}]}, _, members}, _options, env) do
    base = Macro.expand(base, env)

    Enum.map(members, fn {:__aliases__, _, parts} ->
      module = Module.concat([base | parts])
      {Module.concat([List.last(parts)]), module}
    end)
  end

  defp alias_pairs(module, options, env) do
    module = Macro.expand(module, env)
    as = options |> List.flatten() |> Keyword.get(:as)

    short =
      if as,
        do: Macro.expand(as, %{env | aliases: []}),
        else: module |> Module.split() |> List.last() |> then(&Module.concat([&1]))

    [{short, module}]
  end
end
