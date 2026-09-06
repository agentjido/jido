# Controlled Turn Agent

- **ID:** `01_05_controlled_turn_agent`
- **Status:** implemented
- **Complexity level:** 1 - Foundation
- **Feature group:** basic
- **Test class:** local deterministic SDK integration
- **Tests:** 3

## SDK obligation

Turn serialization, cancellation, queued work, and caller timeout.

## Acceptance cases

- Queued work starts after the prior Turn and receives its committed state.
- Cancellation stops abandoned execution, preserves queued work, and rejects a stale Turn ID.
- Caller timeout ends waiting while the started Turn can still commit once.

- Queued calls keep separate caller context. Cancellation does not pass abandoned context to the next Turn. The observer PID stays outside Signal data.

## Implementation and evidence

- [Source](../../../../examples/01_basic/01_05_controlled_turn_agent/controlled_turn_agent.ex)
- [Integration tests](../../../../test/examples/01_basic/01_05_controlled_turn_agent/controlled_turn_agent_test.exs)
- [Basic results](../../basic-results.md)

The fixture uses real Jido components. Local observers and barriers control
only observations and timing. Domain commands use Signals. These cases prove
SDK boundaries; they do not claim durable recovery or live-service behavior.
