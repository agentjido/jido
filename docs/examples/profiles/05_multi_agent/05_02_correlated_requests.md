# Correlated Requests

Feature ID: `05_02_correlated_requests`. Status: implemented within the tested scope.

## Added feature

Pending parent state, independent child work, and a later correlated reply form separate Turns. Read this after the Runtime group and the previous Multi-agent example.

## Use

```elixir
alias Jido.Examples.CorrelatedRequests

{:ok, server} = Jido.start_agent(jido, CorrelatedRequests)
CorrelatedRequests.request(server, "request-1", 7)
```

## Evidence

6 enabled tests:

- the child completes its own Turn before the parent accepts the result.
- wrong correlation and duplicate requests cannot settle pending work.
- cancellation stops the child and its active execution worker.
- child process loss ends the request and a fresh request can succeed.
- a child Action error becomes a failed request through the stop-on-error policy.
- the child execution deadline ends blocked work and settles the parent.

Run:

```shell
mix test --include integration test/examples/05_multi_agent/05_02_correlated_requests --seed 0
```

[Source](../../../../lib/examples/05_multi_agent/05_02_correlated_requests/correlated_requests.ex) ·
[Tests](../../../../test/examples/05_multi_agent/05_02_correlated_requests/correlated_requests_test.exs)

## Boundary and next question

Child errors use an explicit stop-on-error policy and a one-second execution deadline. Requests are local and transient; retry identity and recovery are application policy.

See the [gap register](../../runtime-multi-agent-gaps.md) and
[verification report](../../runtime-multi-agent-results.md).
