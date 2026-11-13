# 04_06 Agent callbacks

Customize new state and portable snapshots through the three public Agent
callbacks.

## What you will learn

- `initialize/2` transforms new candidate state before schema validation.
- `checkpoint/2` writes a custom portable state payload.
- `restore/2` rebuilds an instance under the saved definition.

## Read the code

Read [the callback Agent](callback_agent.ex) first.

## Run it

`mix test.examples examples/04_agents/04_06_agent_callbacks --warnings-as-errors`

Expected result: initialization adds the Agent ID, and a custom public snapshot
restores the exact Agent value.

## Important behavior

`Jido.Persistence.snapshot/2` and `restore/2` own the callback envelope and
portability checks. Application code must not treat the callback payload alone
as a complete snapshot.

## Limits

These callbacks convert Agent data. They do not start runtime resources or run
post-commit effects.

## Files

- [Source](callback_agent.ex)
- [Tests](callback_agent_test.exs)

Previous: [Replies and Directives](../04_05_replies_and_directives/README.md) | Next: [Agent views](../04_07_agent_views/README.md)

