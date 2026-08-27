defmodule Jido.Agent.DSL.MacroSupport do
  @moduledoc false

  @doc false
  def validate_options!(options, caller, label) do
    if Keyword.keyword?(options) do
      case first_duplicate(Keyword.keys(options)) do
        nil -> :ok
        field -> compile_error!(caller, "duplicate #{label} field: #{inspect(field)}")
      end
    else
      compile_error!(caller, "#{label} options must be a keyword list")
    end
  end

  @doc false
  def source(caller), do: Macro.escape(%{line: caller.line})

  @doc false
  def compile_error!(caller, description) do
    raise CompileError, file: caller.file, line: caller.line, description: description
  end

  defp first_duplicate(values) do
    values
    |> Enum.reduce_while(MapSet.new(), fn value, seen ->
      if MapSet.member?(seen, value),
        do: {:halt, value},
        else: {:cont, MapSet.put(seen, value)}
    end)
    |> then(fn
      %MapSet{} -> nil
      duplicate -> duplicate
    end)
  end
end

defmodule Jido.Agent.DSL.Macros do
  @moduledoc false

  alias Jido.Agent.DSL.MacroSupport

  @route_match_error "agent route matches must be stable external unary function captures"

  defmacro plugin(module, options) do
    entity(module, options, extension_module("Plugin"), :__plugin__, __CALLER__)
  end

  defmacro plugin(module) do
    entity(module, [], extension_module("Plugin"), :__plugin__, __CALLER__)
  end

  defmacro route(path, target, options) do
    validate_route_match!(options, __CALLER__)
    entity([path, target], options, extension_module("Route"), :__route__, __CALLER__)
  end

  defmacro route(path, target) do
    entity([path, target], [], extension_module("Route"), :__route__, __CALLER__)
  end

  defmacro schedule(name, cron_expression, signal_type, options) do
    entity(
      [name, cron_expression, signal_type],
      options,
      extension_module("Schedule"),
      :__schedule__,
      __CALLER__
    )
  end

  defmacro schedule(name, cron_expression, signal_type) do
    entity(
      [name, cron_expression, signal_type],
      [],
      extension_module("Schedule"),
      :__schedule__,
      __CALLER__
    )
  end

  defp entity(arguments, options, module, function, caller) do
    MacroSupport.validate_options!(options, caller, "Agent declaration")
    source = MacroSupport.source(caller)
    arguments = List.wrap(arguments)

    case Keyword.pop(options, :do) do
      {nil, short_options} ->
        quote generated: true, line: caller.line, file: caller.file do
          require unquote(module)

          unquote(module).unquote(function)(
            unquote_splicing(arguments),
            unquote(source),
            unquote(short_options)
          )
        end

      {block, []} ->
        quote generated: true, line: caller.line, file: caller.file do
          require unquote(module)

          unquote(module).unquote(function)(
            unquote_splicing(arguments),
            unquote(source)
          ) do
            unquote(block)
          end
        end

      {_block, _mixed_options} ->
        MacroSupport.compile_error!(
          caller,
          "do not mix keyword and block fields in one Agent declaration"
        )
    end
  end

  defp validate_route_match!(options, caller) when is_list(options) do
    options
    |> Keyword.get(:match)
    |> validate_match_ast!(caller)
  end

  defp validate_route_match!(_options, _caller), do: :ok

  defp validate_match_ast!(nil, _caller), do: :ok

  defp validate_match_ast!({:&, _meta, [{:/, _slash_meta, [remote, 1]}]}, caller)
       when is_tuple(remote) do
    case remote do
      {{:., _dot_meta, [_module, function]}, _call_meta, []} when is_atom(function) -> :ok
      _local -> MacroSupport.compile_error!(caller, @route_match_error)
    end
  end

  defp validate_match_ast!(value, _caller) when is_function(value, 1), do: :ok

  defp validate_match_ast!(_value, caller),
    do: MacroSupport.compile_error!(caller, @route_match_error)

  defp extension_module(name), do: Module.concat(Jido.Agent.DSL.Extension.Agent, name)
end
