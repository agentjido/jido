defmodule Jido.Examples.Patterns.SupportDesk.Reasoning do
  @moduledoc "Routes each request through admission before the tool-enabled reasoning Flow."

  alias Jido.AI.Reasoning.ReAct
  alias Jido.AI.Reasoning.Result

  defmodule Reject do
    alias Jido.Joi

    use Jido.Action, name: "examples_support_desk_reject", schema: Joi.map()

    @impl true
    def run(_params, %{agent_state: state}) do
      {:ok, %{state: state, response: Result.blocked(:input, "Ask about a device or support ticket.")}}
    end
  end

  defmodule Admit do
    alias Jido.Joi

    use Jido.Action, name: "examples_support_desk_admit", schema: Joi.map()

    @impl true
    def run(%{input: input} = request, _context) when is_binary(input) do
      excerpt = input |> String.split(" Also, ", parts: 2) |> hd() |> String.trim()

      if String.length(excerpt) in 1..500 and
           String.contains?(String.downcase(excerpt), ["printer", "ticket", "device", "support"]) do
        {:ok, %{request: %{request | input: excerpt}}}
      else
        {:ok, %{}}
      end
    end

    def run(_request, _context), do: {:ok, %{}}
  end

  defmodule Expand do
    alias Jido.Joi

    use Jido.Action, name: "examples_support_desk_expand", schema: Joi.map()

    @impl true
    def run(%{request: request}, _context), do: {:continue, request, ReAct}
    def run(_decision, _context), do: {:continue, %{}, Reject}
  end

  use Jido.Flow,
    id: "examples/support-desk/reasoning",
    vsn: 1,
    name: "examples_support_desk_reasoning",
    schema: ReAct.schema(),
    output_schema: ReAct.output_schema()

  flow do
    invoke "answer",
      decision: Admit,
      expander: Expand,
      params: %{
        input: input(:input),
        instructions: input(:instructions),
        model: input(:model),
        options: input(:options),
        stream: false,
        context: %{max_messages: 16, max_bytes: 24_000},
        limits: %{model_calls: 2, tool_calls: 1, tool_rounds: 1, retries: 0, elapsed_ms: 5_000}
      }

    output result("answer")
  end
end
