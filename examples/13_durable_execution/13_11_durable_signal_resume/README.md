# 13_11 Signal Resume

`Jido.Durable` does not own a scheduler. A host calculates a cron occurrence,
builds a `Jido.Signal`, and sends that Signal to an open wait. The Signal
continues the saved Flow.

This example uses `Jido.Plugin.Scheduler.occurrence_signal/5`. An AgentServer
can use the same function and delivery path.

See [the ExUnit proof](signal_resume_test.exs).
