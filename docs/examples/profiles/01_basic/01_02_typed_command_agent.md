# Typed Command Agent

- **ID:** `01_02_typed_command_agent`
- **Status:** implemented
- **Complexity level:** 1 - Foundation
- **Feature group:** basic
- **Test class:** local deterministic SDK integration
- **Tests:** 4

## SDK obligation

Construction, route selection, input validation, and complete candidate validation.

## Acceptance cases

- Direct construction and live startup preserve defaults and root rules, with and without Plugin state.
- Route defaults and Signal data merge before the selected Action validates
  input. Direct and live execution agree. A supplied nested patch replaces the
  default patch; it does not inherit missing fields from that default.
- Invalid supplied values, including `nil`, fail validation before Action
  execution or commit. Non-map Signal data returns a structured error.
- The Action preserves untouched Agent state fields when it applies a patch.
- An invalid complete candidate cannot commit or dispatch its effect.
- Unknown and ambiguous routes return `Jido.Error.RoutingError` through direct
  evaluation and a live Server, with matching public error data and useful
  route details. They execute no Action, commit no state, and dispatch no effect;
  a later valid command succeeds.

- Direct and live execution receive the observer through transient caller context. Signal data contains only command values.

## Implementation and evidence

- [Source](../../../../examples/01_basic/01_02_typed_command_agent/typed_command_agent.ex)
- [Integration tests](../../../../test/examples/01_basic/01_02_typed_command_agent/typed_command_agent_test.exs)
- [Basic results](../../basic-results.md)

The fixture uses real Jido components. Local observers and barriers control
only observations and timing. Domain commands use Signals. These cases prove
SDK boundaries; they do not claim durable recovery or live-service behavior.
