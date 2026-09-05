> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Calculator Action

- **Status:** archived research
- **Complexity level:** 1 - Foundation
- **Feature group:** basic
- **Test class:** local deterministic

## Profile

- **Purpose:** Show a standalone typed Action without an Actor runtime.
- **User story:** As a user, I request one calculation and receive a typed result.
- **Trigger or input:** An Action input map with an operation and two operands.
- **Agent state:** None.
- **Actions or Flow:** One Action selects a local operation and returns a typed result.
- **External interactions:** None.
- **Runtime Directives or capabilities:** None.
- **Expected result:** `Jido.Exec.run/4` returns the validated calculation result.
- **Failure cases:** Divide by zero, unsupported operation, or invalid number.
- **Jido features under pressure:** Action input, Action output, and structured errors.
- **Source framework and links:** [LangGraph: workflows and agents tool example](https://docs.langchain.com/oss/python/langgraph/workflows-agents), and [Basic SDK suite](../../../../test/examples/01_basic/README.md)

## Current scope

This is an archived research profile from the original catalog. Its source
folder and repeated domain tests were removed. It is not a current SDK
acceptance claim. See the [five Basic fixtures](../../../../test/examples/01_basic/README.md)
and [current results](../../basic-results.md) for the implemented obligations.
