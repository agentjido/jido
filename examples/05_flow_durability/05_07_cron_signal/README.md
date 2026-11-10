# 05.07 Cron Signal

`Jido.Durable` does not own a scheduler. A host calculates a cron occurrence,
builds a `Jido.Signal`, and saves that Signal against an open wait. The next
resume continues from the saved checkpoint.

This example uses `Jido.Plugin.Scheduler.occurrence_signal/5`. An AgentServer
can use the same function and delivery path.
