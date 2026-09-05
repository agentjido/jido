# Causal Trace

Feature ID: `04_10_causal_trace`. Status: implemented within the tested scope.

## Added feature

Child creation, work, results, retries, restore, and restart retain explicit
trace and cause identities across local and remote Agent Turns.

## Evidence

Twelve core tests cover local and two-node causation, terminal failure,
creation retry, restore, replacement, and OTP restart.

```shell
mix test test/jido/observe/causal_trace_test.exs test/jido/observe/remote_causal_trace_test.exs --seed 0
```

[Source](../../../../lib/examples/04_runtime/04_10_causal_trace/causal_trace.ex) ·
[Core tests](../../../../test/jido/observe/causal_trace_test.exs) ·
[Results](../../obs-02-results.md)
