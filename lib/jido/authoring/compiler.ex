defmodule Jido.Authoring.Compiler do
  @moduledoc false

  @doc false
  @spec compile_contract(:action | :flow, map()) ::
          {:ok, map()} | {:error, String.t()}
  def compile_contract(kind, opts) do
    contract =
      %{
        "id" => Map.fetch!(opts, :id),
        "vsn" => Map.fetch!(opts, :vsn),
        "kind" => Atom.to_string(kind),
        "name" => Map.fetch!(opts, :name),
        "description" => Map.get(opts, :description),
        "input_schema" => compile_json_schema(opts.schema, :schema),
        "output_schema" => compile_json_schema(opts.output_schema, :output_schema)
      }
      |> Jason.encode!(maps: :strict)
      |> Jason.decode!()

    {:ok, contract}
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  @doc false
  @spec contract!({:ok, map()} | {:error, String.t()}) :: map() | no_return()
  def contract!({:ok, contract}), do: contract
  def contract!({:error, message}), do: raise(ArgumentError, message)

  defp compile_json_schema([], _option), do: nil

  defp compile_json_schema(schema, option) do
    Zoi.to_json_schema(schema)
  rescue
    exception ->
      raise ArgumentError,
            "#{inspect(option)} does not have a JSON-safe JSON Schema representation: " <>
              Exception.message(exception)
  end
end
