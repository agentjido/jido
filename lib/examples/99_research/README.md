# Jido capability research queue (`99_research`)

This folder retains four narrative scope items, the enabled DIST-03 probe, and
three completed persistence regression examples. Their numeric IDs stay fixed
for migration tracking. Core contract tests remain under `test/jido`.

| Queue | Capability | Open question |
| --- | --- | --- |
| [99_01_progress_observation](99_01_progress_observation/README.md) | `OBS-03` | How do clients observe progress and waiting reasons with bounded delivery? |
| [99_02_distributed_authority](99_02_distributed_authority/README.md) | `DIST-03` | Who owns one logical Agent identity across Erlang nodes? |
| [99_03_input_resource_lifecycle](99_03_input_resource_lifecycle/README.md) | `CTRL-01` | How does an input Plugin own, replace, and close a disposable resource? |
| [99_04_handoff_reconciliation](99_04_handoff_reconciliation/README.md) | `CTRL-02` | How does live work transfer ownership and recover after partial failure? |
| [99_05_capacity_deadlines_cleanup](99_05_capacity_deadlines_cleanup/README.md) | `CTRL-03` | How does Jido bound work and account for cleanup under load? |
| [99_06_checkpoint_identity](99_06_checkpoint_identity/README.md) | `PERSIST-01` | Does a loaded Agent have the requested identity? |
| [99_07_checkpoint_portability](99_07_checkpoint_portability/README.md) | `PERSIST-02` | Does load reject process-local checkpoint values? |
| [99_08_indeterminate_write](99_08_indeterminate_write/README.md) | `PERSIST-03` | Does an unknown write result prevent further Action work on stale state? |

`DIST-03` is paused at the cluster ownership boundary. Its enabled two-node
acceptance test proves revision fencing, then exposes the missing global owner
claim. Four items remain acceptance plans and have no placeholder tests.
The three persistence probes have 10 passing tests, with no skipped assertions.
Their in-memory adapter tests the core contract without
a database or VM restart. See the [persistence results](../../../docs/examples/persistence-boundary-results.md).

The solved capabilities now live in the main sequence:

- `OBS-01`, `OBS-02`, `REC-01`, `REC-02`, and `REC-03` are Runtime examples.
- `DIST-01` and `DIST-02` are Multi-agent examples.
- The 48 archived application sketches remain in the documentation archive and
  Git history at commit `bd05a32`.

See the [capability ledger](../../../docs/examples/research-capabilities.md) and
the [DIST-03 evidence](../../../docs/examples/dist-03-results.md).
