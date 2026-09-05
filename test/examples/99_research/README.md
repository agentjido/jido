# Jido feature acceptance examples

The 2026-09-05 passes add 13 executable feature probes against unchanged core.
All 45 checks are enabled: **34 pass and 11 fail across nine proposed core features**.
The first ten probes cover general core features. Three more cover live Agent
and topology upgrades. A failed check records required behavior; do not skip
it or reverse its assertion.

## Run

```sh
mix test test/examples/99_research --include example --seed 0
```

This selection returns a failing exit status while the 11 missing-contract
assertions remain unmet. It uses no vendor API or model request. The distributed
example starts two local Erlang nodes. Each row has its own focused command.

| ID | Feature | Pass | Fail | Result |
| --- | --- | ---: | ---: | --- |
| FA-01 | [Route precedence and fixed selection](99_09_route_selection/README.md) | 2 | 2 | Core feature required |
| FA-02 | [Plugin read and prepared-input isolation](99_10_plugin_isolation/README.md) | 2 | 2 | Core feature required |
| FA-03 | [Stable Agent references and durable namespace identity](99_11_stable_reference/README.md) | 2 | 1 | Core feature required; application reference works |
| FA-04 | [Definition revision checks on restore](99_12_definition_revision/README.md) | 1 | 1 | Core feature required |
| FA-05 | [Durable deletion](99_13_durable_delete/README.md) | 2 | 1 | Core feature required |
| FA-06 | [Plugin runtime reconstruction from committed state](99_03_input_resource_lifecycle/README.md) | 1 | 1 | Core feature required; public pull recovery works |
| FA-07 | [Progress observation with recovery](99_01_progress_observation/README.md) | 5 | 0 | Works as an application extension |
| FA-08 | [Acknowledged handoff and worker reconciliation](99_04_handoff_reconciliation/README.md) | 3 | 0 | Works as an application protocol |
| FA-09 | [Shared work budgets](99_05_capacity_deadlines_cleanup/README.md) | 3 | 0 | Works as a local runtime extension |
| FA-10 | [Fenced distributed ownership](99_02_distributed_authority/README.md) | 4 | 0 | Works with an explicit external authority |
| UP-01 | [Turn upgrade](99_14_turn_upgrade/README.md) | 2 | 1 | Core feature required |
| UP-02 | [State migration](99_15_state_migration/README.md) | 3 | 1 | Compatible state migration works; definition upgrade required |
| UP-07 | [Topology upgrade](99_16_topology_upgrade/README.md) | 4 | 1 | Plan comparison and full replacement work; live update required |

[Complete result log](../../../docs/examples/feature-acceptance-results.md)
records each missing contract, proof limits, and validation commands.

[Live-upgrade cases and results](../../../docs/examples/live-upgrade-results.md)
records all ten upgrade targets, the three new examples, and their limits.

## Retained research

The original IDs remain stable. The ten probes use existing folders 99_01
through 99_05 and new folders 99_09 through 99_13. Three older completed
persistence probes remain under 99_06 through 99_08. Their core regression
tests remain under test/jido/persistence.
The live-upgrade examples use new folders 99_14 through 99_16.

The original DIST-03 source probe and its core tests remain available. The
core-only exclusive-owner test retains its previously approved skip. The four
new fencing checks have no skips and use an explicit external authority.

These tests stay in test/examples because this pass adds examples and records
core requirements. It does not implement or change core contracts. Existing
CI excludes test/examples; the full command with --include example runs them.
