> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Tool Permission Gate

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_26_tool_permission_gate`
- **Status:** implemented
- **Complexity level:** 4 - Runtime safety
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Apply deterministic allow, ask, or deny policy before an Action or Flow performs a tool effect.
- **User story:** As an operator, I prevent unsafe tool calls and require approval for sensitive work.
- **Trigger or input:** A work Signal contains a requested mock tool operation and its resource targets.
- **Agent state:** Work status, requested operation, policy decision, approval reference, result, and bounded audit facts.
- **Actions or Flow:** One Flow calls an explicit policy Action before the tool Action. An `allow` result continues. A `deny` result stops with a structured error. An `ask` result commits pending state and waits for a new approval Signal.
- **External interactions:** Local policy adapter, fake approval input, and fake filesystem tool.
- **Runtime Directives or capabilities:** An approval notification Directive can notify an input adapter. The later approval returns as a new Signal.
- **Expected result:** Denied work has no tool effect. Allowed work runs once. Approval work does not block the Actor mailbox and runs only after a valid approval Signal.
- **Failure cases:** Missing rule, conflicting rule, malformed path, symlink alias, stale approval, wrong approver, repeated approval, policy failure, or tool failure after approval.
- **Jido features under pressure:** Explicit effect boundary, structured policy result, multi-Turn approval, idempotency, Signal correlation, and audit data minimization.
- **Source framework and links:** [Pi permission-system package](https://pi.dev/packages/@gotgenes/pi-permission-system) and [Pi safety extension examples](https://github.com/earendil-works/pi/tree/main/packages/coding-agent/examples/extensions)

## Design constraint

This example must not add a generic Plugin hook around every Action. The Flow
must show the permission decision as program composition. Runtime code only
owns approval delivery and supervised resources.


## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/runtime/04_26_tool_permission_gate/tool_permission_gate.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_26_tool_permission_gate/tool_permission_gate_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
