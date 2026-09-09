# Jido feature acceptance examples

The research set has 13 executable feature probes. The current result has
**42 passing checks and 3 skipped live-upgrade checks**.
The first ten probes cover general core features. Three more cover live Agent
and Topology upgrades. Each skip names a deferred feature and keeps its
assertion.

## Run

```sh
mix test test/examples/99_research --include example --seed 0
```

This is an optional secondary check. It excludes the 3 skipped live-upgrade
assertions. It uses no vendor API or model request. The distributed
example starts two local Erlang nodes. Each row has its own focused command.

| ID | Feature | Pass | Skipped | Result |
| --- | --- | ---: | ---: | --- |
| FA-01 | [Route precedence and fixed selection](99_09_route_selection/README.md) | 4 | 0 | Core feature available |
| FA-02 | [Plugin read and prepared-input isolation](99_10_plugin_isolation/README.md) | 4 | 0 | Core feature available |
| FA-03 | [Stable Agent references and durable namespace identity](99_11_stable_reference/README.md) | 3 | 0 | Implemented and executable |
| FA-04 | [Definition revision checks on restore](99_12_definition_revision/README.md) | 2 | 0 | Core feature available |
| FA-05 | [Durable deletion](99_13_durable_delete/README.md) | 3 | 0 | Implemented and executable |
| FA-06 | [Plugin runtime reconstruction from committed state](99_03_input_resource_lifecycle/README.md) | 2 | 0 | Implemented and executable |
| FA-07 | [Progress observation with recovery](99_01_progress_observation/README.md) | 5 | 0 | Works as an application extension |
| FA-08 | [Acknowledged handoff and worker reconciliation](99_04_handoff_reconciliation/README.md) | 3 | 0 | Works as an application protocol |
| FA-09 | [Shared work budgets](99_05_capacity_deadlines_cleanup/README.md) | 3 | 0 | Works as a local runtime extension |
| FA-10 | [Fenced distributed ownership](99_02_distributed_authority/README.md) | 4 | 0 | Works with an explicit external authority |
| UP-01 | [Turn upgrade](99_14_turn_upgrade/README.md) | 2 | 1 | Core feature required |
| UP-02 | [State migration](99_15_state_migration/README.md) | 3 | 1 | Compatible state migration works; definition upgrade required |
| UP-07 | [Topology upgrade](99_16_topology_upgrade/README.md) | 4 | 1 | Plan comparison and full replacement work; live update required |

The tables and focused README files record each missing contract, proof limit,
validation command, and live-upgrade result. Executable tests are the current
evidence.

## Retained research

The original IDs remain stable. The ten probes use existing folders 99_01
through 99_05 and new folders 99_09 through 99_13. Three older completed
persistence probes remain under 99_06 through 99_08. Their core regression
tests remain under test/jido/persistence.
The live-upgrade examples use new folders 99_14 through 99_16.

The original DIST-03 source probe and its core tests remain available. The
core-only exclusive-owner test retains its previously approved skip. The four
new fencing checks have no skips and use an explicit external authority.

These tests stay in test/examples because they record core requirements.
Existing CI excludes test/examples; the full command with `--include example`
runs them.
