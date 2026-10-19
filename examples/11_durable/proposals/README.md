# Durable design proposals

These files retain design decisions and test plans. They have no executable
lesson source and do not count as example coverage. IDs remain stable.

Start with the [integration checklist](flow-control/INTEGRATION.md).
The current executable wait lesson is [11_06 Durable Wait](../11_06_durable_wait/README.md).
It covers Signal matching, timer selection, hibernation, thaw, and deadline
identity in one Flow. Its expiry test uses the same Step Actions with a zero
duration, so no test waits one hour.

| ID | Design and remaining proof | Test plan |
| --- | --- | --- |
| 11_08 | [flow signal wait](11_08_flow_signal_wait/README.md) | [Plan](11_08_flow_signal_wait/test-plan.md) |
| 11_09 | [flow timer](11_09_flow_timer/README.md) | [Plan](11_09_flow_timer/test-plan.md) |
| 11_10 | [signal selection](11_10_signal_selection/README.md) | [Plan](11_10_signal_selection/test-plan.md) |
| 11_11 | [suspended activation](11_11_suspended_activation/README.md) | [Plan](11_11_suspended_activation/test-plan.md) |
| 11_12 | [ninety day flow](11_12_ninety_day_flow/README.md) | [Plan](11_12_ninety_day_flow/test-plan.md) |
| 11_13 | [topology wait](11_13_topology_wait/README.md) | [Plan](11_13_topology_wait/test-plan.md) |
| 11_14 | [recovery compatibility](11_14_recovery_compatibility/README.md) | [Plan](11_14_recovery_compatibility/test-plan.md) |
| 11_15 | [execution rollover](11_15_execution_rollover/README.md) | [Plan](11_15_execution_rollover/test-plan.md) |
| 11_16 | [retry recovery](11_16_retry_recovery/README.md) | [Plan](11_16_retry_recovery/test-plan.md) |
| 11_17 | [turn receipts](11_17_turn_receipts/README.md) | [Plan](11_17_turn_receipts/test-plan.md) |
| 11_18 | [composed recovery](11_18_composed_recovery/README.md) | [Plan](11_18_composed_recovery/test-plan.md) |
| 11_19 | [failed work recovery](11_19_failed_work_recovery/README.md) | [Plan](11_19_failed_work_recovery/test-plan.md) |

11_08–11_12 overlap the supported wait lesson. Retain them as design history
and remaining policy questions. Do not create five duplicate runnable lessons.
Long wall-clock runs, early input, clock jumps, topology input, compatibility,
rollover, retry recovery, receipts, composed recovery, and failed-work policy
need their stated evidence before promotion.
