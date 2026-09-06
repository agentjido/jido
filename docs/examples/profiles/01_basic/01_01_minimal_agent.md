# Minimal Agent

- **ID:** `01_01_minimal_agent`
- **Status:** implemented
- **Complexity level:** 1 - Foundation
- **Feature group:** basic
- **Test class:** local deterministic SDK integration
- **Tests:** 3

## SDK obligation

Direct/live agreement and instance isolation.

## Acceptance cases

- Direct evaluation and Server execution agree when empty Signal data uses the
  route's default amount and when a supplied amount overrides that default.
- Two instances from one definition keep separate state, identity, and registry entries.

- A zero increment returns the same Agent. The live Server still advances its commit revision once.
- The Action rejects invalid amounts before its body runs. A later
  valid command can still commit.

Startup uses the Jido instance API directly. The instance-isolation case also
proves generated IDs, caller-exit independence, duplicate-ID rejection, and
structured errors for invalid options and IDs. The command case checks that
the explicit increment helper preserves Server options and result tuples.

## Implementation and evidence

- [Source](../../../../examples/01_basic/01_01_minimal_agent/minimal_agent.ex)
- [Integration tests](../../../../test/examples/01_basic/01_01_minimal_agent/minimal_agent_test.exs)
- [Basic results](../../basic-results.md)

The fixture uses real Jido components. Local observers and barriers control
only observations and timing. Domain commands use Signals. These cases prove
SDK boundaries; they do not claim durable recovery or live-service behavior.
