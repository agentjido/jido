# 05 Flow Durability

These supported offline lessons use the current `Jido.Exec`,
`Jido.Durable`, and `Runic.Runner` contracts.

| ID | Lesson |
| --- | --- |
| `05_01_run_identity` | Inspect one managed execution identity. |
| `05_02_snapshot_and_resume` | Restore a completed checkpoint. |
| `05_03_process_recovery` | Restore interrupted pending work. |
| `05_04_run_inspection` | Inspect active and complete work. |
| `05_05_cancellation` | Cancel active Map work. |
| `05_06_telemetry` | Correlate Jido and Runic telemetry. |
| `05_07_cron_signal` | Deliver a host-built cron occurrence Signal to a durable wait. |
| `05_08_timed_wait` | Resume a durable timer from its saved wake time. |
| `05_09_direct_flow` | Run one durable Flow without an Agent or AgentServer. |

Run the supported group with:

```sh
mix test.examples test/examples/05_flow_durability
```
