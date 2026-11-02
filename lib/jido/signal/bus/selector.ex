defmodule Jido.Signal.Bus.Selector do
  @moduledoc false

  alias Jido.Signal

  @max_value_bytes 4_096
  @value_schema Zoi.string() |> Zoi.refine({__MODULE__, :validate_value_size, []})
  @schema Zoi.keyword(
            [
              source:
                @value_schema
                |> Zoi.refine({Signal, :validate_uri_reference, []})
                |> Zoi.optional(),
              subject:
                @value_schema
                |> Zoi.refine({Signal, :validate_utf8_string, []})
                |> Zoi.optional()
            ],
            unrecognized_keys: :error
          )

  @type match :: (Signal.t() -> boolean())

  @doc false
  @spec compile(term()) :: {:ok, match()} | {:error, {:invalid_selector, String.t()}}
  def compile(selector) do
    if valid_shape?(selector) do
      case Zoi.parse(@schema, selector) do
        {:ok, fields} -> {:ok, compile_match(fields)}
        {:error, errors} -> {:error, {:invalid_selector, Zoi.prettify_errors(errors)}}
      end
    else
      {:error, {:invalid_selector, "must contain :source and/or :subject once each"}}
    end
  end

  @doc false
  def validate_value_size(value, _opts) when byte_size(value) in 1..@max_value_bytes, do: :ok

  def validate_value_size(_value, _opts),
    do: {:error, "must contain 1 to #{@max_value_bytes} bytes"}

  defp valid_shape?(source: _), do: true
  defp valid_shape?(subject: _), do: true
  defp valid_shape?(source: _, subject: _), do: true
  defp valid_shape?(subject: _, source: _), do: true
  defp valid_shape?(_selector), do: false

  defp compile_match(fields) do
    case {Keyword.get(fields, :source), Keyword.get(fields, :subject)} do
      {source, nil} ->
        fn
          %Signal{source: ^source} -> true
          _signal -> false
        end

      {nil, subject} ->
        fn
          %Signal{subject: ^subject} -> true
          _signal -> false
        end

      {source, subject} ->
        fn
          %Signal{source: ^source, subject: ^subject} -> true
          _signal -> false
        end
    end
  end
end
