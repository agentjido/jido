defmodule Jido.Flow.DSL.MacroSupport do
  @moduledoc false

  alias Jido.Authoring.Options

  @doc false
  @spec validate_options!(term(), Macro.Env.t(), String.t(), String.t()) :: :ok | no_return()
  defdelegate validate_options!(options, caller, options_message, duplicate_label),
    to: Options,
    as: :validate!

  @doc false
  @spec entity(list(), keyword(), module(), atom(), Macro.Env.t(), {String.t(), String.t()}) ::
          Macro.t() | no_return()
  def entity(arguments, options, module, function, caller, {label, mixed_label}) do
    validate_options!(
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
        compile_error!(caller, "do not mix keyword and block fields in #{mixed_label}")
    end
  end

  @doc false
  @spec source(Macro.Env.t()) :: Macro.t()
  def source(caller), do: Macro.escape(%{line: caller.line})

  @doc false
  @spec compile_error!(Macro.Env.t(), String.t()) :: no_return()
  defdelegate compile_error!(caller, description), to: Options, as: :error!
end
