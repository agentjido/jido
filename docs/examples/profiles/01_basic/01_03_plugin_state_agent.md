# Plugin State Agent

- **ID:** `01_03_plugin_state_agent`
- **Status:** implemented
- **Complexity level:** 1 - Foundation
- **Feature group:** basic
- **Test class:** local deterministic SDK integration
- **Tests:** 3

## SDK obligation

Plugin state ownership and atomic domain/Plugin commit.

## Acceptance cases

- Domain and Plugin state appear in the same committed snapshot, including to a Directive handler.
- An Action cannot overwrite Plugin-owned state.
- Invalid Plugin output rejects the whole candidate and preserves the prior commit and effects.

## Implementation and evidence

- [Source](../../../../lib/examples/01_basic/01_03_plugin_state_agent/plugin_state_agent.ex)
- [Integration tests](../../../../test/examples/01_basic/01_03_plugin_state_agent/plugin_state_agent_test.exs)
- [Basic results](../../basic-results.md)

The fixture uses real Jido components. Local observers and barriers control
only observations and timing. Domain commands use Signals. These cases prove
SDK boundaries; they do not claim durable recovery or live-service behavior.
