defmodule Jido.Flow.DSL.Authoring do
  @moduledoc false

  alias Jido.Instruction.Config
  alias Jido.Flow.Definition

  @step_names :__jido_flow_step_names__

  @doc false
  @spec entity(
          [Macro.t()],
          term(),
          module(),
          atom(),
          Macro.Env.t(),
          {String.t(), String.t()}
        ) :: Macro.t()
  def entity(arguments, options, module, function, caller, {label, mixed_label}) do
    Config.validate_options!(
      options,
      caller,
      "#{label} options must be a keyword list",
      "#{label} field"
    )

    arguments = arguments ++ [source(caller)]

    case Keyword.pop(options, :do) do
      {nil, short_options} ->
        quote generated: true, line: caller.line, file: caller.file do
          require unquote(module)

          unquote(module).unquote(function)(
            unquote_splicing(arguments),
            unquote(short_options)
          )
        end

      {block, []} ->
        quote generated: true, line: caller.line, file: caller.file do
          require unquote(module)

          unquote(module).unquote(function)(unquote_splicing(arguments)) do
            unquote(block)
          end
        end

      {_block, _mixed_options} ->
        Config.compile_error!(caller, "do not mix keyword and block fields in #{mixed_label}")
    end
  end

  @doc false
  @spec source(Macro.Env.t()) :: Macro.t()
  def source(caller), do: Macro.escape(%{line: caller.line})

  @doc false
  @spec register_step!(term(), Macro.Env.t()) :: String.t()
  def register_step!(value, env) do
    name = declaration_name!(value, env)
    names = Module.get_attribute(env.module, @step_names) || MapSet.new()

    if MapSet.member?(names, name) do
      Config.compile_error!(env, "duplicate Step name: #{inspect(name)}")
    end

    Module.put_attribute(env.module, @step_names, MapSet.put(names, name))
    name
  end

  @doc false
  @spec declaration_name!(term(), Macro.Env.t()) :: String.t()
  def declaration_name!(value, env) do
    case Definition.name(value) do
      {:ok, name} -> name
      {:error, error} -> Config.compile_error!(env, Exception.message(error))
    end
  end
end
