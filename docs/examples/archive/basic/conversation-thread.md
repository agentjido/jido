> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Conversation Thread

- **Status:** archived research
- **Complexity level:** 1 - Foundation
- **Feature group:** basic
- **Test class:** local deterministic

## Profile

- **Purpose:** Show that conversation history is ordinary application state.
- **User story:** As a user, I add messages and retrieve a stable conversation history.
- **Trigger or input:** Append message Signal with a role and content.
- **Agent state:** An ordered list of application-defined messages.
- **Actions or Flow:** One Action validates and appends one message.
- **External interactions:** None.
- **Runtime Directives or capabilities:** None.
- **Expected result:** Messages have stable order after one commit per append.
- **Failure cases:** Invalid role or empty content.
- **Jido features under pressure:** Ordinary Actor state, typed message input, and deterministic ordering.
- **Source framework and links:** [Pi Agent Core: state and messages](https://github.com/earendil-works/pi/tree/main/packages/agent), and [Basic SDK suite](../../../../test/examples/01_basic/README.md)

## Current scope

This is an archived research profile from the original catalog. Its source
folder and repeated domain tests were removed. It is not a current SDK
acceptance claim. See the [five Basic fixtures](../../../../test/examples/01_basic/README.md)
and [current results](../../basic-results.md) for the implemented obligations.
