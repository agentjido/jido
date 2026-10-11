defmodule ParallelSearch.CallToolTest do
  use ExUnit.Case, async: true

  setup do
    bypass = Bypass.open()
    owner = self()

    Bypass.stub(bypass, "POST", "/mcp", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      send(owner, {:request, conn.request_path, conn.req_headers, request})

      result =
        case request["method"] do
          "initialize" ->
            %{
              "protocolVersion" => "2025-03-26",
              "capabilities" => %{"tools" => %{}},
              "serverInfo" => %{"name" => "fixture", "version" => "1"}
            }

          "tools/list" ->
            %{
              "tools" =>
                Enum.map(
                  ["web_search", "web_fetch"],
                  &%{"name" => &1, "inputSchema" => %{"type" => "object"}}
                )
            }

          "tools/call" ->
            if request["params"]["arguments"]["fail"] do
              %{
                "isError" => true,
                "content" => [%{"type" => "text", "text" => "private remote error"}]
              }
            else
              %{
                "content" => [
                  %{"type" => "text", "text" => "Elixir documentation https://elixir-lang.org"}
                ],
                "structuredContent" => %{"fixture" => true}
              }
            end

          _ ->
            nil
        end

      if result do
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"jsonrpc" => "2.0", "id" => request["id"], "result" => result})
        )
      else
        Plug.Conn.resp(conn, 202, "")
      end
    end)

    opts =
      Keyword.put(ParallelSearch.Client.options(), :url, "http://localhost:#{bypass.port}/mcp")

    client =
      start_supervised!(%{
        id: ExMCP.Client,
        start: {ExMCP.Client, :start_link, [opts]},
        restart: :temporary
      })

    %{client: client, bypass: bypass}
  end

  test "anonymous configuration selects the remote MCP endpoint" do
    opts = ParallelSearch.Client.options()
    assert opts[:url] == "https://search.parallel.ai/mcp"
    assert opts[:transport] == :http
    assert opts[:security] == %{trusted_origins: ["https://search.parallel.ai"]}
    assert opts[:headers] == [{"user-agent", "jido-parallel-search-example/0.1.0"}]
  end

  test "discovery and both tools use the HTTP MCP caller and project headers", %{client: client} do
    assert {:ok, %{"tools" => tools}} = ExMCP.Client.list_tools(client, format: :map)
    assert Enum.map(tools, & &1["name"]) == ["web_search", "web_fetch"]

    for {tool, arguments} <- [
          {"web_search",
           %{
             "objective" => "Find Elixir docs",
             "search_queries" => ["official Elixir language docs"],
             "session_id" => "fixture-session"
           }},
          {"web_fetch",
           %{"urls" => ["https://elixir-lang.org"], "session_id" => "fixture-session"}}
        ] do
      assert {:ok, %{mcp_result: result}} =
               Jido.Exec.run(
                 ParallelSearch.CallTool,
                 %{tool: tool, arguments: arguments},
                 %{mcp_client: client},
                 max_retries: 0
               )

      assert result["content"] == [
               %{"type" => "text", "text" => "Elixir documentation https://elixir-lang.org"}
             ]

      assert result["structuredContent"] == %{"fixture" => true}

      assert_receive {:request, "/mcp", call_headers,
                      %{
                        "method" => "tools/call",
                        "params" => %{"name" => ^tool, "arguments" => ^arguments}
                      }}

      assert {"user-agent", "jido-parallel-search-example/0.1.0"} in call_headers
      refute Enum.any?(call_headers, fn {name, _} -> name == "authorization" end)
    end

    assert_receive {:request, "/mcp", initialize_headers, %{"method" => "initialize"}}
    assert_receive {:request, "/mcp", discovery_headers, %{"method" => "tools/list"}}

    for headers <- [initialize_headers, discovery_headers] do
      assert {"user-agent", "jido-parallel-search-example/0.1.0"} in headers
      refute Enum.any?(headers, fn {name, _} -> name == "authorization" end)
    end
  end

  test "remote tool failures return structured errors without remote text", %{client: client} do
    assert {:error, error} =
             Jido.Exec.run(
               ParallelSearch.CallTool,
               %{tool: "web_search", arguments: %{"fail" => true}},
               %{mcp_client: client},
               max_retries: 0
             )

    assert Exception.message(error) =~ "Parallel MCP tool reported an error"
    refute inspect(error) =~ "private remote error"
  end

  test "connection failures return a structured error", %{client: client, bypass: bypass} do
    Bypass.down(bypass)

    assert {:error, error} =
             Jido.Exec.run(
               ParallelSearch.CallTool,
               %{tool: "web_fetch", arguments: %{"urls" => ["https://elixir-lang.org"]}},
               %{mcp_client: client},
               max_retries: 0
             )

    assert Exception.message(error) =~ "Parallel MCP request failed"
  end

  test "missing context and unsupported tools are rejected" do
    assert {:error, _} =
             Jido.Exec.run(ParallelSearch.CallTool, %{tool: "web_search", arguments: %{}}, %{},
               max_retries: 0
             )

    assert {:error, _} =
             Jido.Exec.run(ParallelSearch.CallTool, %{tool: "other_tool", arguments: %{}}, %{},
               max_retries: 0
             )
  end
end
