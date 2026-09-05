# Scheduling

Declare `Jido.Plugin.Scheduler` explicitly. Use its typed directives to schedule
Signals, cancel work, and acknowledge durable occurrences. Scheduler state belongs
to the Plugin. Heartbeat supplies periodic input. The old Scheduler wrapper,
Agent `schedules` declarations, and native cron directives are removed.

Durable occurrences retain a stable identity for repeated delivery of one slot.
Different scheduled instants have different identities. The supplied clock waits
until its scheduled instant before delivery. Custom clocks keep their own contract.
The example commits business state and acknowledgement together. It skips other
busy or offline slots according to its stated policy; it does not promise to
replay every missed interval.

See [scheduled occurrence tests](../test/jido/agent/scheduled_occurrence_test.exs)
and [recovery tests](../test/jido/agent/scheduled_occurrence_recovery_test.exs).
