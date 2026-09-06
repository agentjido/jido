defmodule Jido.Examples.LLM.Adapter do
  @moduledoc """
  Example-owned external service contract. Clients enter through caller context.
  Jido supplies execution and commit rules; this module supplies no SDK policy.
  """
  alias Jido.Action.Error

  @callback call(term(), atom(), map()) :: {:ok, term()} | {:error, term()}

  def request(context, key, operation, input) do
    case context[key] do
      {module, client} when is_atom(module) -> module.call(client, operation, input)
      _ -> {:error, {:missing_client, key}}
    end
  end

  def call(context, key, operation, input) do
    case request(context, key, operation, input) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, Error.execution_error("#{operation} failed", reason: reason)}
      other -> {:error, Error.validation_error("invalid adapter response", response: other)}
    end
  end

  def parse(schema, value) do
    case Zoi.parse(schema, value) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, issues} -> {:error, Error.validation_error("invalid model data", issues: issues)}
    end
  end

  def answer_schema, do: Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)})
  def prompt_schema, do: Zoi.object(%{prompt: Zoi.string() |> Zoi.min(1)})

  def signal(type, input), do: Jido.Signal.new!("llm.#{type}", input, source: "/examples/llm")
  def invalid(message), do: {:error, Error.validation_error(message)}
end
