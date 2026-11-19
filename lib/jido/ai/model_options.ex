defmodule Jido.AI.ModelOptions do
  @moduledoc false

  alias Jido.Joi

  @known_keys ReqLLM.Provider.Options.all_generation_keys() ++
                Keyword.keys(ReqLLM.Embedding.schema().schema) ++
                [:output, :output_validation]
  @keys_by_name Map.new(@known_keys, &{Atom.to_string(&1), &1})

  def schema do
    Joi.map() |> Joi.transform({__MODULE__, :normalize, []})
  end

  def normalize(options, _context \\ [])

  def normalize(options, _context) when is_map(options) and not is_struct(options) do
    Enum.reduce_while(options, {:ok, %{}}, fn {key, value}, {:ok, normalized} ->
      case option_key(key) do
        :error ->
          {:halt, {:error, "model option key must be an atom or a known option name"}}

        {:ok, key} when is_map_key(normalized, key) ->
          {:halt, {:error, "duplicate model option #{key}"}}

        {:ok, key} ->
          {:cont, {:ok, Map.put(normalized, key, value)}}
      end
    end)
  end

  def normalize(_options, _context), do: {:error, "model options must be a map"}

  defp option_key(key) when is_atom(key), do: {:ok, key}
  defp option_key(key), do: Map.fetch(@keys_by_name, key)
end
