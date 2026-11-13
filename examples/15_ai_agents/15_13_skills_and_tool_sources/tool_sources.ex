defmodule Jido.Examples.AI.SkillsAndToolSources.OfflineMCPSource do
  @moduledoc "Models the ToolSource boundary that jido_connect supplies for MCP."

  @behaviour Jido.AI.ToolSource

  @impl true
  def list_tools(%{server: server}, _context) when is_binary(server) do
    {:ok,
     [
       %{
         name: "remote_lookup",
         description: "Look up one value through the configured offline server fixture.",
         parameter_schema: [
           query: [type: :string, required: true, doc: "Lookup query"]
         ]
       }
     ]}
  end

  def list_tools(_config, _context), do: {:error, :invalid_server_config}

  @impl true
  def run_tool(%{name: "remote_lookup", arguments: arguments}, %{server: server}, _context) do
    query = Map.get(arguments, :query, Map.get(arguments, "query"))

    if is_binary(query) and query != "" do
      {:ok, %{query: query, result: "offline result", server: server}}
    else
      {:error, :invalid_query}
    end
  end

  def run_tool(%{name: name}, _config, _context), do: {:error, {:unknown_tool, name}}
end
