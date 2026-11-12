# 05.01 Start and Result

`Jido.Durable.start/4` runs a Flow from a `Jido.Signal`. It saves the execution
through a normal Jido persistence adapter. It does not require an Agent or an
AgentServer. Configure the adapter on the Jido instance. A durable operation
cannot select or replace that adapter.

The completed status contains a portable reference. Pass this reference to
`Jido.Durable.status/2` or `Jido.Durable.result/2`. The result has the same
shape as `Jido.Exec.run/4`.

See [the ExUnit proof](start_and_result_test.exs).
