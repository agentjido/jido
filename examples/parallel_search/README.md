# Parallel Search MCP actions

Run web search and page fetching as Jido actions with the maintained [ExMCP](https://hexdocs.pm/ex_mcp/) client and [Parallel Search MCP](https://docs.parallel.ai/integrations/mcp/search-mcp). The anonymous endpoint needs no account or API key. Search uses Fast mode; free-tier requests have lower rate limits and capped excerpts.

This companion app uses the Jido checkout through a path dependency. Its MCP dependencies stay in this example app.

## Run

With Elixir 1.18+ and Erlang/OTP 27+ installed, start from the repository root:

```sh
cd examples/parallel_search
mix deps.get
mix run scripts/search.exs
# Or supply a search objective:
mix run scripts/search.exs "Find official Elixir OTP supervision documentation"
```

The script discovers `web_search` and `web_fetch`, calls both through `Jido.Exec.run`, and prints their complete MCP results. Fetch reads the fixed Elixir introduction page, independently of the search objective. Both calls share a fresh session ID. It does not load credentials, start a model, or run an agent reasoning loop.

## Reuse the action

Start `ParallelSearch.Client`, then pass its PID as `mcp_client` in the action context. `ParallelSearch.CallTool` accepts `tool` (`"web_search"` or `"web_fetch"`) and `arguments` (the tool's argument map). Use the schemas returned by `ExMCP.Client.list_tools(client, format: :map)` for current server inputs.

`web_search` requires an `objective` and at least one `search_queries` entry. Prefer focused objectives and related 3–6 word queries. `web_fetch` accepts up to 20 HTTP(S) URLs; its optional objective is limited to 200 characters. Reuse one `session_id` across related calls. Leave `model_name` unset unless you have an actual model identifier from your runtime.

The action returns `{:ok, %{mcp_result: result}}` with the full MCP envelope, or a structured Jido error for a failed request/tool. The connection uses Streamable HTTP, a project User-Agent and a 30-second request timeout. Calls are not automatically retried. Stop the client in an `after` block when finished.

Keep HTTP work in actions executed by the runtime or action runner. Do not move it into a pure agent decision function. Untrusted fetched content is data, not instructions.

## Test

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

Tests use a local MCP server fixture and do not contact Parallel.
