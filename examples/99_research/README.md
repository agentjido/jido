# Research probes

These probes record implemented contracts and application extensions that are
not Jido core APIs. Checkpoint identity, portability, and durable delete also
have stable lessons in the [Persistence guide](../../guides/storage.md).
Do not copy a research pattern into an application without reading its status
and limits.

## Application extensions

1. [Progress Observation](99_01_progress_observation/README.md) — bounded temporary progress outside Agent state.
2. [Distributed Authority](99_02_distributed_authority/README.md) — external fencing across local Erlang nodes.
3. [Input Resource Lifecycle](99_03_input_resource_lifecycle/README.md) — runtime reconstruction from Plugin state.
4. [Handoff Reconciliation](99_04_handoff_reconciliation/README.md) — acknowledged request ownership in application state.
5. [Shared Budget](99_05_capacity_deadlines_cleanup/README.md) — one local admission budget for several teams.

## Persistence and routing contracts

6. [Checkpoint Identity](99_06_checkpoint_identity/README.md)
7. [Checkpoint Portability](99_07_checkpoint_portability/README.md)
8. [Indeterminate Write](99_08_indeterminate_write/README.md)
9. [Route Selection](99_09_route_selection/README.md)
10. [Plugin Isolation](99_10_plugin_isolation/README.md)
11. [Stable Reference](99_11_stable_reference/README.md)
12. [Definition Revision](99_12_definition_revision/README.md)
13. [Durable Delete](99_13_durable_delete/README.md)

## Upgrade contracts

14. [Turn Upgrade](99_14_turn_upgrade/README.md)
15. [State Migration](99_15_state_migration/README.md)
16. [Topology Upgrade](99_16_topology_upgrade/README.md)

## Run the section

```sh
mix test test/examples/99_research --include example --seed 0
```

Expected result: every enabled probe passes. The distributed-authority probe
starts two local Erlang nodes. Research failures must name a missing contract;
they must not be hidden with an example-only production shim.

## Promotion rule

Promote a probe only after the public API is stable, its normal usage is clear,
and it has a concise place in sections `01` through `08`. Remove the research
copy after promotion unless it still proves a separate boundary.
