> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Counter

- **Status:** archived research
- **Complexity level:** 1 - Foundation
- **Feature group:** basic
- **Test class:** local deterministic

## Profile

- **Purpose:** Show the smallest useful Actor state transition.
- **User story:** As a learner, I send one Signal and observe one state change.
- **Trigger or input:** Increment Signal with a signed integer amount.
- **Agent state:** `count`.
- **Actions or Flow:** One Action returns the complete next state.
- **External interactions:** None.
- **Runtime Directives or capabilities:** None.
- **Expected result:** One Signal selects one Action and commits `count` one time.
- **Failure cases:** None at this level. Bounded Counter covers rejected input.
- **Jido features under pressure:** Actor schema, one Signal route, one Action result, and one commit.
- **Source framework and links:** [Akka: introduction to Actors](https://doc.akka.io/libraries/akka-core/current/typed/actors.html), and [Basic SDK suite](../../../../test/examples/01_basic/README.md)

## Current scope

This is an archived research profile from the original catalog. Its source
folder and repeated domain tests were removed. It is not a current SDK
acceptance claim. See the [five Basic fixtures](../../../../test/examples/01_basic/README.md)
and [current results](../../basic-results.md) for the implemented obligations.
