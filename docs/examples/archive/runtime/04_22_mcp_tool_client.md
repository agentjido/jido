> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# MCP Tool Client

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_22_mcp_tool_client`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced runtime
- **Feature group:** runtime
- **Test class:** true integration

## Profile

- **Purpose:** Discover and call tools from an MCP server through a managed connection.
- **User story:** As an agent author, I add remote tools without writing a custom adapter for each tool.
- **Trigger or input:** Tool discovery, tool call, connection change, or server notification Signal.
- **Agent state:** Server identity, approved tool schemas, capability revision, and call summaries.
- **Actions or Flow:** A Flow selects an approved tool and validates its input and output.
- **External interactions:** MCP server over standard transport.
- **Runtime Directives or capabilities:** Jido needs an MCP Plugin for connection lifecycle, discovery, calls, cancellation, and notifications.
- **Expected result:** Only approved schemas are callable and connection changes are visible.
- **Failure cases:** Schema change, untrusted server, transport loss, timeout, invalid result, or prompt injection.
- **Jido features under pressure:** No current built-in MCP capability, dynamic schemas, long-lived connection, and security.
- **Source framework and links:** [CrewAI: MCP servers as tools](https://docs.crewai.com/en/mcp/overview), [Mastra: MCP](https://mastra.ai/docs/mcp/overview), [PydanticAI: MCP](https://pydantic.dev/docs/ai/mcp/)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/runtime/04_22_mcp_tool_client/mcp_tool_client.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_22_mcp_tool_client/mcp_tool_client_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: Discovery and approved calls work through a fake adapter. Managed MCP transport, reconnect, notifications, and cancellation are not implemented.

An example-scope gap is not evidence of a core Jido defect.
