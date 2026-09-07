# UP-07: Topology upgrade

The baseline has four passing tests and one failure. As of 2026-09-07,
the failing test is temporarily skipped, with its assertion retained.
See the [research test policy](../README.md).

A pure Agent plan comparison finds additions, removals, changed definitions, and unchanged entries. The second worker definition changes real behavior. Invalid target validation has no live effects. Full controller replacement grows three workers to five and restores saved state, but replaces every PID.

## Required core feature

Submission of a live target through current Controller startup returns already_started. Core needs a separate update operation that retains unchanged members and changes the repair target.

## Run

```sh
mix test test/examples/99_research/99_16_topology_upgrade --include example --seed 0 --trace
```

This is a secondary check. The skipped assertion states desired upgrade
behavior. When the explicit upgrade API exists, connect this example to it
and remove the skip. Current startup and ordinary Turn APIs retain their
existing contracts.

## Scope

The comparison covers local Agent entries only. It does not handle Bus resources, ownership, subscriptions, same-module code revisions, rolling batches, or durable rollout recovery.

[Source](../../../../examples/99_research/99_16_topology_upgrade/topology_upgrade.ex) · [Tests](topology_upgrade_test.exs)

[All ten upgrade cases and results](../../../../docs/examples/live-upgrade-results.md)
