defmodule Jido.Examples.ModelResponse.Generate do
  @moduledoc false
  alias Jido.Action.Error
  alias Jido.Examples.LLM.Adapter
  use Jido.Action, name: "llm_model_response", schema: Adapter.prompt_schema()

  def run(input, context) do
    response =
      case Adapter.request(context, :model, :complete, input) do
        {:error, reason} when reason in [:timeout, :overloaded, :rate_limited] ->
          Adapter.call(context, :backup, :complete, input)

        {:ok, result} ->
          {:ok, result}

        {:error, reason} ->
          {:error, Error.execution_error("model failed", reason: reason)}

        _ ->
          Adapter.invalid("invalid provider response")
      end

    with {:ok, raw} <- response,
         {:ok, result} <- Adapter.parse(Adapter.answer_schema(), raw) do
      {:ok, %{answer: result.answer}}
    end
  end
end

defmodule Jido.Examples.ModelResponse do
  @moduledoc "One typed model call. Transient-error fallback is application policy."

  use Jido.Agent, name: "llm_model_response_agent"

  agent do
    schema Zoi.object(%{answer: Zoi.string() |> Zoi.default("")})
  end

  routes do
    signal_source "/examples/llm"

    route "llm.response", Jido.Examples.ModelResponse.Generate do
      define :generate, args: [:prompt]
    end
  end
end
