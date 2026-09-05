> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Dynamic Tool Catalog

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_06_dynamic_tool_catalog`
- **Status:** implemented
- **Complexity level:** 3 - Tool selection
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Find and activate only the tools that one Agent Turn needs.
- **User story:** As an Agent author, I use a large tool collection without adding all tool definitions to each model request.
- **Trigger or input:** A user Signal asks for work that needs one tool from a large local catalog.
- **Agent state:** User request, selected tool ID and version, tool input, tool result, and final answer.
- **Actions or Flow:** One Flow searches a typed catalog, loads the selected descriptor, calls one fake tool, and returns the complete next state.
- **External interactions:** Local catalog and lazy fake provider. The provider records when it starts and which tool runs.
- **Runtime Directives or capabilities:** None for the basic case. A provider that needs a process can use an explicit supervised capability.
- **Expected result:** The Flow exposes only the selected tool description, starts only its provider, calls it once, and commits once.
- **Failure cases:** No match, ambiguous match, invalid schema, unavailable provider, stale descriptor, denied tool, bad arguments, timeout, or invalid result.
- **Jido features under pressure:** Typed Action discovery, lazy activation, Flow composition, provider isolation, context size, and structured tool errors.
- **Source framework and links:** [Pi MCP Adapter](https://pi.dev/packages/pi-mcp-adapter), [Pi custom and dynamic tool examples](https://github.com/earendil-works/pi/tree/main/packages/coding-agent/examples/extensions), and [Pi extension API](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md)


## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/runtime/04_06_dynamic_tool_catalog/dynamic_tool_catalog.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_06_dynamic_tool_catalog/dynamic_tool_catalog_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
