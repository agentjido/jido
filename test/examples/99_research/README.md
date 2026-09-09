# Jido feature acceptance examples

The research set has 16 executable feature probes. The current result has 48
passing checks and no skipped checks. Ten probes cover general core features,
three retained probes cover persistence boundaries, and three cover bounded
live Agent and Topology upgrades.

## Run

```sh
mix test test/examples/99_research --include example --seed 0
```

This is an optional secondary check, not the default release check. It uses no
vendor API or model request. The distributed example starts two local Erlang
nodes. Each row has its own focused command.

| ID | Feature | Baseline pass | Skipped | Result |
| --- | --- | ---: | ---: | --- |
| FA-01 | [Route precedence and fixed selection](99_09_route_selection/README.md) | 4 | 0 | Core feature available |
| FA-02 | [Plugin read and prepared-input isolation](99_10_plugin_isolation/README.md) | 4 | 0 | Core feature available |
| FA-03 | [Stable Agent references and durable namespace identity](99_11_stable_reference/README.md) | 3 | 0 | Implemented and executable |
| FA-04 | [Definition revision checks on restore](99_12_definition_revision/README.md) | 2 | 0 | Implemented and executable |
| FA-05 | [Durable deletion](99_13_durable_delete/README.md) | 3 | 0 | Implemented and executable |
| FA-06 | [Plugin runtime reconstruction from committed state](99_03_input_resource_lifecycle/README.md) | 2 | 0 | Implemented and executable |
| FA-07 | [Progress observation with recovery](99_01_progress_observation/README.md) | 5 | 0 | Works as an application extension |
| FA-08 | [Acknowledged handoff and worker reconciliation](99_04_handoff_reconciliation/README.md) | 3 | 0 | Works as an application protocol |
| FA-09 | [Shared work budgets](99_05_capacity_deadlines_cleanup/README.md) | 3 | 0 | Works as a local runtime extension |
| FA-10 | [Fenced distributed ownership](99_02_distributed_authority/README.md) | 4 | 0 | Works with an explicit external authority |
| PERSIST-01 | [Checkpoint identity](99_06_checkpoint_identity/README.md) | 1 | 0 | Core loader rejects mismatched identity |
| PERSIST-02 | [Checkpoint portability](99_07_checkpoint_portability/README.md) | 1 | 0 | Core loader rejects runtime-only values |
| PERSIST-03 | [Indeterminate write](99_08_indeterminate_write/README.md) | 1 | 0 | Core blocks stale work after an uncertain write |
| UP-01 | [Turn upgrade](99_14_turn_upgrade/README.md) | 3 | 0 | Core provides an explicit quiescent upgrade boundary |
| UP-02 | [State migration](99_15_state_migration/README.md) | 4 | 0 | Core validates and checkpoints live definition migration |
| UP-07 | [Topology upgrade](99_16_topology_upgrade/README.md) | 5 | 0 | Core supports additive local target updates |

The tables and focused README files record the contracts, proof limits,
validation commands, and live-upgrade results. Executable tests and their tags
define the current result.

## Retained research

The original IDs remain stable. The ten probes use existing folders 99_01
through 99_05 and new folders 99_09 through 99_13. Three completed persistence
probes remain under 99_06 through 99_08. Each has a small example test and a
deeper core regression suite.
The live-upgrade examples use new folders 99_14 through 99_16.

The original DIST-03 source probe and its core tests remain available. The
core-only exclusive-owner test retains its previously approved skip. The four
new fencing checks have no skips and use an explicit external authority.

These tests stay in test/examples because they record executable example
contracts. Existing CI excludes test/examples; `mix examples --seed 0` selects
them separately.
