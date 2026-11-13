defmodule Jido.Formatter do
  @moduledoc false

  @behaviour Mix.Tasks.Format

  @impl true
  def features(_opts), do: [extensions: [".ex", ".exs"]]

  @impl true
  def format(contents, opts) do
    {line_length, formatter_opts} = Keyword.pop(opts, :line_length, 98)

    parser_opts =
      [
        unescape: false,
        literal_encoder: &{:ok, {:__block__, &2, [&1]}},
        token_metadata: true,
        emit_warnings: false
      ] ++ formatter_opts

    {forms, comments} = Code.string_to_quoted_with_comments!(contents, parser_opts)

    forms =
      Macro.prewalk(forms, fn
        {name, metadata, arguments} = call
        when is_atom(name) and is_list(arguments) and is_list(metadata) ->
          if declaration?(name, arguments) do
            metadata = Keyword.drop(metadata, [:closing, :newlines])
            {name, metadata, arguments}
          else
            call
          end

        node ->
          node
      end)

    formatted =
      forms
      |> Code.Formatter.to_algebra([comments: comments] ++ formatter_opts)
      |> Inspect.Algebra.format(line_length)

    IO.iodata_to_binary([formatted, "\n"])
  end

  defp declaration?(:await, [_name, options]), do: option?(options, :event)
  defp declaration?(:timer, [_name, options]), do: option?(options, :after_ms)
  defp declaration?(_name, _arguments), do: false

  defp option?(options, expected) when is_list(options) do
    Enum.any?(options, fn
      {{:__block__, _metadata, [^expected]}, _value} -> true
      {^expected, _value} -> true
      _option -> false
    end)
  end

  defp option?(_options, _expected), do: false
end
