# Directive Agent

- **ID:** `01_04_directive_agent`
- **Status:** implemented
- **Complexity level:** 1 - Foundation
- **Feature group:** basic
- **Test class:** local deterministic SDK integration
- **Tests:** 3

## SDK obligation

Whole-batch validation and ordered post-commit dispatch.

## Acceptance cases

- Handlers run in list order and each reads the committed snapshot and source context.
- An invalid later Directive prevents the entire commit and all dispatch.
- A failed second dispatch keeps the commit, reports failure, and skips the third effect.

Each acceptance case runs twice: once with the recording Plugin process and
once with `StatelessEffects`, which has no Plugin process. Both callbacks run
through the real Server task and use the same validation and error contract.
Core tests also check dispatch timeout, task death, and result Signals.

## Implementation and evidence

- [Source](../../../../lib/examples/01_basic/01_04_directive_agent/directive_agent.ex)
- [Integration tests](../../../../test/examples/01_basic/01_04_directive_agent/directive_agent_test.exs)
- [Basic results](../../basic-results.md)

The fixture uses real Jido components. Local observers and barriers control
only observations and timing. Domain commands use Signals. These cases prove
SDK boundaries; they do not claim durable recovery or live-service behavior.
