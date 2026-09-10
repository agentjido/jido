defmodule Jido.Examples.LLM.Adapter do
  @moduledoc """
  The external service contract shared by the LLM examples.

  Clients enter through Turn context. This module is example support and does
  not define a Jido model API.
  """

  alias Jido.Action.Error

  @callback call(term(), atom(), map()) :: {:ok, term()} | {:error, term()}

  @spec request(map(), atom(), atom(), map()) :: {:ok, term()} | {:error, term()}
  def request(context, key, operation, input) do
    case context[key] do
      {module, client} when is_atom(module) -> module.call(client, operation, input)
      _other -> {:error, {:missing_client, key}}
    end
  end

  @spec call(map(), atom(), atom(), map()) ::
          {:ok, term()} | {:error, Error.ExecutionFailureError.t()}
  def call(context, key, operation, input) do
    case request(context, key, operation, input) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, Error.execution_error("#{operation} failed", reason: reason)}
    end
  end

  @spec parse(Zoi.schema(), term()) :: {:ok, term()} | {:error, Error.InvalidInputError.t()}
  def parse(schema, value) do
    case Zoi.parse(schema, value) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, issues} -> {:error, Error.validation_error("invalid model data", issues: issues)}
    end
  end

  @spec answer_schema() :: Zoi.schema()
  def answer_schema, do: Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)})

  @spec prompt_schema() :: Zoi.schema()
  def prompt_schema, do: Zoi.object(%{prompt: Zoi.string() |> Zoi.min(1)})

  @spec invalid(String.t()) :: {:error, Error.InvalidInputError.t()}
  def invalid(message), do: {:error, Error.validation_error(message)}
end
