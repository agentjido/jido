# ADR 0016 FSM Plugin namespace

- Status: Accepted
- Date: 2026-11-21

## Context

The V3 beta shipped the bundled FSM under the same namespace as the generic
Agent Plugin callbacks.

## Decision

Use `Jido.Plugin.FSM` as the public namespace. Give `jido.plugin.fsm`
ownership of the FSM implementation in the Reach capabilities layer. Keep
the `state_machine` section and the `jido.fsm` Catalog ID at version 1.

## Consequences

Beta applications must update their Agent declarations to use
`Jido.Plugin.FSM`. Durable records retain their original provider fingerprint
and require an explicit upgrade.

## References

- [FSM migration](../../guides/reference/v2-to-v3-migration.md#upgrade-the-beta-fsm-plugin)
- [FSM obligations](../../test/contracts/jido.plugin/fsm.obligations.md)
