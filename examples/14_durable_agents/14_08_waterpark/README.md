# 14.08 Waterpark

This example proves the durable Agent activation model in one Jido Instance.
It creates 20 long-lived Agents. Normal delivery uses `Jido.Agent.Ref`, not a
process identifier. Active Agents stay warm for a short time. Idle Agents
passivate and restore from the same durable state.

The ExUnit test also proves these cases:

- A worker restart keeps the activation ID.
- Passivation and reactivation change the activation ID.
- A matching Signal resumes a durable Flow Turn.
- The Instance wake capability delivers a due timer to a passivated Agent.
- The resident activation count returns to zero after the idle timeout.

The example does not start another Instance or BEAM node. It has no mesh,
placement, or remote routing code. A later mesh can route the same Agent Ref to
the owning Instance without a change to AgentServer.

Run the bounded proof:

```sh
mix test.examples examples/14_durable_agents/14_08_waterpark --warnings-as-errors
```

Read [the ExUnit proof](waterpark_test.exs) with the
[Waterpark Agents](waterpark.ex).

`Jido.Examples.Durable.Waterpark.load/3` is an optional local load helper. Its
default count is 1,000 Agents. It is not part of the normal test run.

Previous: [External Uncertainty](../14_07_external_uncertainty/README.md)
