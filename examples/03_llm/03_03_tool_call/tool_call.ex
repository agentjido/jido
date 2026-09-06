defmodule Jido.Examples.ToolCall.Search do
  @moduledoc "The one approved typed tool Action. Read permission is an application rule."
  alias Jido.Examples.LLM.Adapter

  use Jido.Action,
    name: "llm_search_tool",
    schema:
      Zoi.object(%{
        id: Zoi.string() |> Zoi.min(1),
        query: Zoi.string() |> Zoi.min(1),
        operation: Zoi.enum([:read])
      })

  def run(input, context) do
    with {:ok, result} <-
           Adapter.call(context, :tools, :search, Map.take(input, [:query, :operation])) do
      {:ok, %{id: input.id, result: result}}
    end
  end
end

defmodule Jido.Examples.ToolCall.Admit do
  @moduledoc "Validate a complete plan before any tool effect. Model names never become modules."
  alias Jido.Examples.LLM.Adapter

  def call_schema,
    do:
      Zoi.object(%{
        id: Zoi.string() |> Zoi.min(1),
        name: Zoi.enum(["search"]),
        arguments: Zoi.object(%{query: Zoi.string() |> Zoi.min(1), operation: Zoi.enum([:read])})
      })

  def plan(raw) do
    with {:ok, calls} <- Adapter.parse(Zoi.list(call_schema()) |> Zoi.max(8), raw) do
      if length(Enum.uniq_by(calls, & &1.id)) == length(calls),
        do: {:ok, Enum.map(calls, &Map.put(&1.arguments, :id, &1.id))},
        else: Adapter.invalid("duplicate tool call ID")
    end
  end
end

defmodule Jido.Examples.ToolCall.Finish do
  @moduledoc false
  alias Jido.Examples.LLM.Adapter
  use Jido.Action, name: "llm_tool_finish"

  def run(input, context) do
    with {:ok, raw} <- Adapter.call(context, :model, :finish, input),
         {:ok, output} <- Adapter.parse(Adapter.answer_schema(), raw) do
      {:ok, %{answer: output.answer, tool_results: input.results}}
    end
  end
end

defmodule Jido.Examples.ToolCall.Pipeline do
  @moduledoc "A selected tool name resolves to a fixed Action before execution."
  alias Jido.Examples.LLM.Adapter
  alias Jido.Examples.ToolCall.Admit
  use Jido.Flow, name: "llm_single_tool_flow", schema: Adapter.prompt_schema()

  flow do
    step "select" do
      action prompt <- input(:prompt),
             name: "llm_select_tool",
             schema: Adapter.prompt_schema(),
             context: context do
        with {:ok, raw} <- Adapter.call(context, :model, :select, %{prompt: prompt}),
             {:ok, [call]} <- Admit.plan([raw]),
             do: {:ok, call}
      end
    end

    step "tool", action: Jido.Examples.ToolCall.Search, params: result("select")

    step "answer",
      action: Jido.Examples.ToolCall.Finish,
      params: %{prompt: input(:prompt), results: [result("tool")]}

    output result("answer")
  end
end

defmodule Jido.Examples.ToolCall do
  @moduledoc "One model-selected typed tool, correlated by call ID, followed by a checked answer."

  use Jido.Agent, name: "llm_tool_agent"

  agent do
    schema Zoi.object(%{
             answer: Zoi.string() |> Zoi.default(""),
             tool_results: Zoi.list(Zoi.map()) |> Zoi.default([])
           })
  end

  routes do
    signal_source "/examples/llm"

    route "llm.tool", Jido.Examples.ToolCall.Pipeline do
      define :ask, args: [:prompt]
    end
  end
end
