# Jido capability research queue (`99_research`)

This folder contains the source research queue and its retained regressions. It contains acceptance notes,
not skipped placeholder tests. Add executable behavior under `test/jido` when
work starts on a core contract.

| Queue | Capability | State |
| --- | --- | --- |
| [99_01_progress_observation](99_01_progress_observation/README.md) | `OBS-03` | planned |
| [99_02_distributed_authority](99_02_distributed_authority/README.md) | `DIST-03` | paused on ownership design |
| [99_03_input_resource_lifecycle](99_03_input_resource_lifecycle/README.md) | `CTRL-01` | planned |
| [99_04_handoff_reconciliation](99_04_handoff_reconciliation/README.md) | `CTRL-02` | planned |
| [99_05_capacity_deadlines_cleanup](99_05_capacity_deadlines_cleanup/README.md) | `CTRL-03` | planned |
| [99_06_checkpoint_identity](99_06_checkpoint_identity/README.md) | `PERSIST-01` | three tests pass; identity rejection retained |
| [99_07_checkpoint_portability](99_07_checkpoint_portability/README.md) | `PERSIST-02` | three tests pass; load rejection retained |
| [99_08_indeterminate_write](99_08_indeterminate_write/README.md) | `PERSIST-03` | four tests pass; later evaluation prevented |

Solved capability tests remain under `test/jido`, beside the core contracts
that they verify. Archived application tests remain in Git history at commit
`bd05a32`.

[Source queue](../../../lib/examples/99_research/README.md) ·
[Capability ledger](../../../docs/examples/research-capabilities.md)
