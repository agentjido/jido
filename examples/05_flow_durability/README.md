# 05 Flow Durability

These supported offline lessons use the current `Jido.Exec` and
`Runic.Runner` contracts.

| ID | Lesson |
| --- | --- |
| `05_01_run_identity` | Inspect one managed execution identity. |
| `05_02_snapshot_and_resume` | Restore a completed checkpoint. |
| `05_03_process_recovery` | Restore interrupted pending work. |
| `05_04_run_inspection` | Inspect active and complete work. |
| `05_05_cancellation` | Cancel active Map work. |
| `05_06_telemetry` | Correlate Jido and Runic telemetry. |

Lessons `03_04`, `03_05`, `03_06`, `03_09`, `03_10`, `03_11`, `03_13`,
and `03_14` have executable deferred probes under `test/system/jido_exec/gaps`.

Run the supported group with:

```sh
mix test.examples test/examples/05_flow_durability
```
