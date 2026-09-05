# Execution after V2 Strategies

The V2 Strategy behavior, FSM Strategy, instruction tracking, and Strategy state
helpers are removed. Route a Signal to one Action or Flow. Keep domain modes and
transition rules in the declared state schema and executable logic.

Use Flow constructs for branching, iteration, and parallel dependency graphs.
Use a new Signal for a later Turn, such as a human approval. Do not port a Strategy
by writing private Agent Server state.

See [Workflow examples](../lib/examples/02_workflow/README.md) and
[the V3 command contract](core-loop.md).
