defmodule ParallelSearch.CallTool do
  @moduledoc "A Jido action for Parallel web search and page fetching over an existing MCP connection."

  use Jido.Action,
    name: "parallel_search_call_tool",
    description: "Search the web or fetch pages with Parallel Search MCP",
    schema:
      Zoi.object(%{
        tool: Zoi.enum(["web_search", "web_fetch"]),
        arguments: Zoi.map()
      })

  @impl true
  def run(params, %{mcp_client: client}) when is_pid(client) do
    case ExMCP.Client.call_tool(client, params.tool, params.arguments,
           format: :map,
           timeout: 30_000,
           retry_policy: false
         ) do
      {:ok, %{"isError" => true}} ->
        {:error, Jido.Action.Error.execution_error("Parallel MCP tool reported an error")}

      {:ok, result} ->
        {:ok, %{mcp_result: result}}

      {:error, _reason} ->
        {:error, Jido.Action.Error.execution_error("Parallel MCP request failed")}
    end
  end

  def run(_params, _context) do
    {:error, Jido.Action.Error.validation_error("An mcp_client PID is required in the context")}
  end
end
