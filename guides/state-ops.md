# State operations after V2

The V2 StateOp structs and StateOps execution pipeline are removed. An Action or
Flow now returns the complete next state. Keep unchanged fields from
`context.agent_state`. For direct domain updates, use `Jido.Agent.set/2`.

Use normal map updates for domain fields. A Plugin owns its declared state key
and updates it through `update_state/3`. Validation checks the complete candidate
before commit, including its optional byte limit. Use a new Signal and command
for each later business-state change.

See [Agent state](agents.md) and the [command contract](core-loop.md).
