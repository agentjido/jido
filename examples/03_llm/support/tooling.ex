defmodule Jido.Examples.LLM.SearchTool do
  @moduledoc """
  The approved typed search Action shared by the single-tool and parallel-tool
  examples.
  """

  alias Jido.Examples.LLM.Adapter

  use Jido.Action,
    name: "examples_llm_search_tool",
    schema:
      Zoi.object(%{
        id: Zoi.string() |> Zoi.min(1),
        query: Zoi.string() |> Zoi.min(1),
        operation: Zoi.enum([:read])
      })

  @impl true
  def run(input, context) do
    with {:ok, result} <-
           Adapter.call(context, :tools, :search, Map.take(input, [:query, :operation])) do
      {:ok, %{id: input.id, result: result}}
    end
  end
end

defmodule Jido.Examples.LLM.ToolPlan do
  @moduledoc """
  Validates a complete model tool plan before any tool effect starts.

  A model tool name is data. The application maps the approved `"search"`
  value to `Jido.Examples.LLM.SearchTool`; it never converts model data to a
  module name.
  """

  alias Jido.Examples.LLM.Adapter

  @spec call_schema() :: Zoi.schema()
  def call_schema do
    Zoi.object(%{
      id: Zoi.string() |> Zoi.min(1),
      name: Zoi.enum(["search"]),
      arguments: Zoi.object(%{query: Zoi.string() |> Zoi.min(1), operation: Zoi.enum([:read])})
    })
  end

  @spec parse(term()) :: {:ok, [map()]} | {:error, term()}
  def parse(raw) do
    with {:ok, calls} <- Adapter.parse(Zoi.list(call_schema()) |> Zoi.max(8), raw) do
      if length(Enum.uniq_by(calls, & &1.id)) == length(calls) do
        {:ok, Enum.map(calls, &Map.put(&1.arguments, :id, &1.id))}
      else
        Adapter.invalid("duplicate tool call ID")
      end
    end
  end
end

defmodule Jido.Examples.LLM.FinishAnswer do
  @moduledoc "The shared final model call for typed tool results."

  alias Jido.Examples.LLM.Adapter

  use Jido.Action,
    name: "examples_llm_finish_tool_answer",
    schema:
      Zoi.object(%{
        prompt: Zoi.string() |> Zoi.min(1),
        results: Zoi.list(Zoi.map())
      })

  @impl true
  def run(input, context) do
    with {:ok, raw} <- Adapter.call(context, :model, :finish, input),
         {:ok, output} <- Adapter.parse(Adapter.answer_schema(), raw) do
      {:ok, %{answer: output.answer, tool_results: input.results}}
    end
  end
end
