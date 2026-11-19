# ADR 0013 Thread proof ownership

- Status: Accepted
- Date: 2026-11-19

## Context

Thread and Entry form a value-model component. Their sequence and codec rules
can be tested without a model or a running Agent. The original conversation
contract gave these rules to the same owner as Session and AI projection.

## Decision

Give `jido.thread` ownership of the ordered history and portable record
obligations. Keep Session revision and AI projection obligations in
`jido_ai.conversation` until those components have their own review decisions.

## Consequences

The Thread proof runs against the value API. Session and projection tests
continue to exercise Thread as a dependency. Existing version 1 maps keep
their fields and sequence rules.

## References

- [Thread review](../components/thread.md)
- [Thread obligations](../../test/contracts/jido/thread.obligations.md)
