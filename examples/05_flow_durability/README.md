# 05 Flow Durability

These lessons show the small `Jido.Durable` contract. A durable run starts
from a `Jido.Signal`, uses the persistence adapter of its Jido instance, and
stops at each authored Flow component boundary.

Use `Jido.Exec.run/4` for an in-memory run. Use `Jido.Durable` only when the
run must survive process or instance replacement. Timers and cron schedules
belong to the host. Durable saves their Flow state but does not start a
scheduler.

| ID | Lesson |
| --- | --- |
| `05_01_start_and_result` | Start from a Signal and read the normal Exec result. |
| `05_02_restart_recovery` | Restore an open wait after a Jido instance restart. |
| `05_03_signal_resume` | Resume a wait with a host-created cron Signal. |
| `05_04_timed_resume` | Resume a saved timer at its reported wake time. |

Run the supported group with:

```sh
mix test.examples examples/05_flow_durability
```
