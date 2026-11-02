# Persistence conformance support

The profile registry is the source of truth for built-in persistence coverage.

## Structure

- `profiles.ex` lists local, service, active, and paused profiles.
- `case.ex` starts an isolated local store and Jido instance.
- `contracts/store.ex` checks reads, byte and token conditions, stale conflicts, and concurrent writers.
- `contracts/agent.ex` checks revision zero, Turn commits, restore policies, hibernate and thaw, and tombstones.
- `contracts/recovery.ex` checks rejected writes and lost replies.
- `fixtures/persistent_probe.ex` is the shared Agent.
- `fixtures/fault_adapter.ex` injects a rejected write or a lost reply after the Agent starts.

`test/jido/persistence/conformance/local_test.exs` generates one ExUnit module for each active local profile. Active service modules use the same contract macros in `test/system/services/`.

## Add an adapter

1. Add the adapter module to `lib/jido/persistence/`.
2. Add one profile entry in `profiles.ex`.
3. Add local setup in `case.ex`, or add an explicit service entry module.
4. Run `mix test.persistence`.
5. Run the relevant service suite when the adapter needs an external service.

A paused profile must have a reason. It does not count as active coverage.
