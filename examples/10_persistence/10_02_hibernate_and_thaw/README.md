# 10_02 Hibernate And Thaw

Hibernation saves an idle Agent and stops its process. Thaw starts a new process from the required record.

## What you will learn

- How to hibernate a persistent Agent.
- How `Jido.thaw/4` requires saved state and restores its revision.

## Read the code

Read [the counter](hibernate_and_thaw.ex), then read its behavior test.

## Run it

`mix test test/examples/10_persistence/10_02_hibernate_and_thaw --include example --seed 0`

Expected result: the old process stops, the new process has the saved count and revision, and a missing required record does not start an Agent.

## Important behavior

Hibernation needs configured persistence. Without it, the call returns `:persistence_not_configured` and the Agent stays live.

## Limits

Hibernate and thaw do not provide cluster ownership or a writer lease.

## Files

- [Source](hibernate_and_thaw.ex)
- [Tests](../../../test/examples/10_persistence/10_02_hibernate_and_thaw/hibernate_and_thaw_test.exs)

Previous: [Persistent Agent](../10_01_persistent_agent/README.md) | Next: [Portable Checkpoint](../10_03_portable_checkpoint/README.md)
