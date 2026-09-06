> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Code Sandbox Session

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_17_code_sandbox_session`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced runtime
- **Feature group:** runtime
- **Test class:** true integration

## Profile

- **Purpose:** Run generated code in an isolated session with fixed limits.
- **User story:** As an analyst, I run several safe calculations that share session files and variables.
- **Trigger or input:** `sandbox.execute` Signal with code, resource policy, and session ID.
- **Agent state:** Session identity, input digest, output references, exit status, and resource use.
- **Actions or Flow:** One Action submits code and validates the returned execution record.
- **External interactions:** Sandbox service or supervised local container.
- **Runtime Directives or capabilities:** A Sandbox Plugin owns create, execute, cancel, expire, and delete commands.
- **Expected result:** Code cannot escape policy, and every session has a terminal cleanup record.
- **Failure cases:** Policy violation, timeout, memory limit, bad output, sandbox crash, or cleanup failure.
- **Jido features under pressure:** Managed resources, cancellation, portable references, secure effects, and TTL cleanup.
- **Source framework and links:** [Google ADK: Agent Runtime Code Execution](https://google.github.io/adk-docs/tools/google-cloud/code-exec-agent-engine/)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/runtime/04_17_code_sandbox_session/code_sandbox_session.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_17_code_sandbox_session/code_sandbox_session_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: The fixture validates an execution record. An isolated sandbox runtime with cancel, expiry, and cleanup is not implemented.

An example-scope gap is not evidence of a core Jido defect.
