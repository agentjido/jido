> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Typed Command Router

- **Status:** archived research
- **Complexity level:** 1 - Foundation
- **Feature group:** basic
- **Test class:** local deterministic

## Profile

- **Purpose:** Show several Signals that select distinct Actions on one Actor.
- **User story:** As a developer, I map stable Signal types to small Actions and reject all other input.
- **Trigger or input:** Create, rename, archive, or restore Signals.
- **Agent state:** Resource name and lifecycle status.
- **Actions or Flow:** Each Signal selects exactly one Action. Each Action returns the full next state.
- **External interactions:** None.
- **Runtime Directives or capabilities:** None.
- **Expected result:** The correct Action runs and one state version commits.
- **Failure cases:** Unknown Signal type, invalid payload, invalid lifecycle transition, or route ambiguity.
- **Jido features under pressure:** Command declaration, route selection, Action isolation, and error contracts.
- **Source framework and links:** [Google ADK: custom agents](https://google.github.io/adk-docs/agents/custom-agents/), and [Basic SDK suite](../../../../test/examples/01_basic/README.md)

## Current scope

This is an archived research profile from the original catalog. Its source
folder and repeated domain tests were removed. It is not a current SDK
acceptance claim. See the [five Basic fixtures](../../../../test/examples/01_basic/README.md)
and [current results](../../basic-results.md) for the implemented obligations.
