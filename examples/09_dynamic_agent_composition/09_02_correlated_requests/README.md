# 09_02 Correlated requests

A coordinator Agent records pending work and accepts only a matching result
from an independently addressed worker.

## What you will learn

- How coordinator and worker use separate Turns and commits.
- How stable request IDs reject stale, duplicate, or unrelated results.

## Read the code

Read [the coordinator Agent](correlated_requests.ex), then read the shared
[Worker Agent](../support/worker.ex).

## Run it

```sh
mix test.examples examples/09_dynamic_agent_composition/09_02_correlated_requests
```

Expected result: the request commits as waiting, the child returns twice the
input, and the parent commits the correlated result.

## Important behavior

The coordinator and worker have stable references and separate canonical
state. A result with the wrong correlation fields does not change the
coordinator commit.

## Limits

This example handles one pending request. It does not define a queue, retry
policy, or durable request ledger.

## Files

- [Source](correlated_requests.ex)
- [Tests](correlated_requests_test.exs)
- [Worker Agent](../support/worker.ex)
Previous: [Child Lifecycle](../09_01_child_lifecycle/README.md) | Next: [Orphan Adoption](../09_03_orphan_adoption/README.md)
