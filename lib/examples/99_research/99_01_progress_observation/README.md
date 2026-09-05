# OBS-03: progress observation

Status: **planned**.

Hold real Agent work with a test barrier. Expose progress and waiting reasons
separately from committed snapshots. A bounded consumer must survive overflow,
disconnect, and reconnect without changing the Agent result. The terminal
result must remain available when a progress event is missed.

Prove waiting for approval, a child result, a retry deadline, and blocked
delivery. Define the public subscription and buffer policy before adding code.

[Research queue](../README.md) ·
[Acceptance notes](../../../../test/examples/99_research/99_01_progress_observation/README.md)
