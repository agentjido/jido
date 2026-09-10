# 05_02 Correlated Requests

A parent Agent records pending work and accepts only the matching result from
its owned child.

## What you will learn

- How parent and child work use separate Turns and commits.
- How stable request IDs reject stale, duplicate, or unrelated results.

## Read the code

Read [the parent Agent](correlated_requests.ex), then read the shared
[Worker Agent](../support/worker.ex) and [Keep State Action](../../support/keep_state.ex).

## Run it

```sh
mix test test/examples/05_multi_agent/05_02_correlated_requests --include example --seed 0
```

Expected result: the request commits as waiting, the child returns twice the
input, and the parent commits the correlated result.

## Important behavior

Cancellation returns explicit child-stop intent. A reused request ID or a result
with the wrong correlation fields does not change the candidate state.

## Limits

This example handles one pending request. It does not define a queue, retry
policy, or durable request ledger.

## Files

- [Source](correlated_requests.ex)
- [Tests](../../../test/examples/05_multi_agent/05_02_correlated_requests/correlated_requests_test.exs)
- [Worker Agent](../support/worker.ex)
- [Keep State Action](../../support/keep_state.ex)

Previous: [Child Lifecycle](../05_01_child_lifecycle/README.md) | Next: [Agent Hierarchy](../05_03_agent_hierarchy/README.md)
