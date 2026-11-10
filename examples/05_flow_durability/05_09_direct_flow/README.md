# 05.09 Direct Flow

`Jido.Durable.start/4` runs a Flow from a `Jido.Signal`. It saves the execution
through a normal Jido persistence adapter. It does not require an Agent or an
AgentServer. Configure the adapter on the Jido instance. A durable operation
cannot select or replace that adapter.
