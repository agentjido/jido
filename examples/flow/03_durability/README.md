# Flow durability examples

These supported offline lessons use the current `Jido.Exec` and
`Runic.Runner` contracts.

| ID | Lesson |
| --- | --- |
| `flow/03_01_run_identity` | Inspect one managed execution identity. |
| `flow/03_02_snapshot_and_resume` | Restore a completed checkpoint. |
| `flow/03_03_process_recovery` | Restore interrupted pending work. |
| `flow/03_07_run_inspection` | Inspect active and complete work. |
| `flow/03_08_cancellation` | Cancel active Map work. |
| `flow/03_12_telemetry` | Correlate Jido and Runic telemetry. |

Lessons `03_04`, `03_05`, `03_06`, `03_09`, `03_10`, `03_11`, `03_13`,
and `03_14` have executable deferred probes under `test/quality/deferred`.

Run the supported group with:

```sh
mix test.examples test/examples/flow/03_durability
```
