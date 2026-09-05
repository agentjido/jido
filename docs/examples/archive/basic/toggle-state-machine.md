> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Toggle State Machine

- **Status:** archived research
- **Complexity level:** 1 - Foundation
- **Feature group:** basic
- **Test class:** local deterministic

## Profile

- **Purpose:** Show explicit state transitions without hidden runtime state.
- **User story:** As a user, I enable, disable, or lock a feature with clear transition rules.
- **Trigger or input:** `toggle.enable`, `toggle.disable`, `toggle.lock`, or `toggle.unlock` Signal.
- **Agent state:** `mode` with `enabled`, `disabled`, or `locked`.
- **Actions or Flow:** One Action uses a transition table and returns the next state.
- **External interactions:** None.
- **Runtime Directives or capabilities:** None.
- **Expected result:** Only allowed transitions commit.
- **Failure cases:** Unknown event, forbidden transition, bad actor state, or repeated command.
- **Jido features under pressure:** Routing, state-machine policy, deterministic `cmd/3`, and structured transition errors.
- **Source framework and links:** [Akka: FSM migration and actor behaviors](https://doc.akka.io/libraries/akka-core/current/typed/from-classic.html), and [Basic SDK suite](../../../../test/examples/01_basic/README.md)

## Current scope

This is an archived research profile from the original catalog. Its source
folder and repeated domain tests were removed. It is not a current SDK
acceptance claim. See the [five Basic fixtures](../../../../test/examples/01_basic/README.md)
and [current results](../../basic-results.md) for the implemented obligations.
