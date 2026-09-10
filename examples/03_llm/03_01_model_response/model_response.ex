defmodule Jido.Examples.ModelResponse do
  @moduledoc "One typed model call with an explicit transient-error fallback policy."

  use Jido.Agent, name: "examples_llm_model_response"

  agent do
    schema Zoi.object(%{answer: Zoi.string() |> Zoi.default("")})
  end

  routes do
    signal_source "/examples/llm/model_response"

    route "examples.llm.model_response.generate" do
      action input,
        schema: Jido.Examples.LLM.Adapter.prompt_schema(),
        context: context do
        alias Jido.Action.Error
        alias Jido.Examples.LLM.Adapter

        response =
          case Adapter.request(context, :model, :complete, input) do
            {:error, reason} when reason in [:timeout, :overloaded, :rate_limited] ->
              Adapter.call(context, :backup, :complete, input)

            {:ok, result} ->
              {:ok, result}

            {:error, reason} ->
              {:error, Error.execution_error("model failed", reason: reason)}
          end

        with {:ok, raw} <- response,
             {:ok, result} <- Adapter.parse(Adapter.answer_schema(), raw) do
          {:ok, %{answer: result.answer}}
        end
      end

      define :generate, args: [:prompt]
    end
  end
end
