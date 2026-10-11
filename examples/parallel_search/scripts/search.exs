# A deterministic action workflow, with no model or agent loop.
objective = Enum.join(System.argv(), " ")

objective =
  if objective == "", do: "Find the official Elixir getting started guide", else: objective

query = objective |> String.split() |> Enum.take(6) |> Enum.join(" ")
session_id = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

outcome =
  with {:ok, client} <- ParallelSearch.Client.start_link() do
    try do
      with {:ok, %{"tools" => tools}} <-
             ExMCP.Client.list_tools(client, format: :map, timeout: 30_000),
           true <-
             Enum.all?(["web_search", "web_fetch"], fn name ->
               Enum.any?(tools, &(&1["name"] == name))
             end),
           {:ok, %{mcp_result: search}} <-
             Jido.Exec.run(
               ParallelSearch.CallTool,
               %{
                 tool: "web_search",
                 arguments: %{
                   "objective" => objective,
                   "search_queries" => [query],
                   "session_id" => session_id
                 }
               },
               %{mcp_client: client},
               timeout: 35_000,
               max_retries: 0
             ),
           {:ok, %{mcp_result: fetch}} <-
             Jido.Exec.run(
               ParallelSearch.CallTool,
               %{
                 tool: "web_fetch",
                 arguments: %{
                   "urls" => ["https://hexdocs.pm/elixir/introduction.html"],
                   "objective" => "Extract the Elixir introduction",
                   "session_id" => session_id
                 }
               },
               %{mcp_client: client},
               timeout: 35_000,
               max_retries: 0
             ) do
        {:ok, %{search: search, fetch: fetch}}
      else
        _ ->
          {:error, "Search or fetch failed; check the connection, inputs and free-tier limits."}
      end
    after
      ExMCP.Client.stop(client)
    end
  else
    _ -> {:error, "Could not connect to Parallel Search MCP."}
  end

case outcome do
  {:ok, results} ->
    IO.puts(Jason.encode!(results, pretty: true))

  {:error, message} ->
    IO.puts(:stderr, message)
    System.halt(1)
end
