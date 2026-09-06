# Factory integration examples

Run the group without a provider key:

```sh
mix test --include example test/examples/06_factory
```

The four folders match the source group. Tests use real Jido and ReqLLM code.
The HTTP boundary returns fixed Anthropic responses. Timing barriers prove
concurrent work and keep assertions independent of provider speed.

The tests cover history, duplicate rejection, provider failure, bounded tool
loops, commands between Agents, feedback during a pending model request,
pause, resume, cancellation, timer completion, department dependencies,
correlated artifacts, failure, and shutdown. Workshop tests also cover the
one-second queue schedule, one active worker, FIFO order, worker cleanup,
worker failure, and model inspection tools. Batch tests cover distinct job IDs,
retries, capacity, input validation, and default or explicit goals.

The shared streaming tests use a local HTTP/SSE server through ReqLLM and Finch.
They cover text before completion, complete tool arguments, history commits,
partial failures, terminal output, factory events, batch submission, and connection cleanup.

For a live run, see the [Factory guide](../../../examples/06_factory/README.md).

The [Flow factory tests](06_04_flow_factory/flow_factory_test.exs) add a larger
graph across nine worker Agents: parallel joins, ordered Map, security Choice,
nested Flows, repair Iterate, accepted handoff, failure, cancellation, deadlines,
and cleanup. The live request path uses local HTTP responses through ReqLLM.
