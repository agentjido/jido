# 05_03 Agent Hierarchy

One recursive Agent definition creates a bounded tree in which each Agent owns
only its direct children.

## What you will learn

- How owned child Directives form a multi-level Agent hierarchy.
- How failure and shutdown clean one branch or the full subtree.

## Read the code

Read [the recursive Agent](agent_hierarchy.ex), then read the shared
[Keep State Action](../../support/keep_state.ex).

## Run it

```sh
mix test test/examples/05_multi_agent/05_03_agent_hierarchy --include example --seed 0
```

Expected result: depth two creates six descendants with correct direct-parent
bindings, and cleanup removes the affected owned processes.

## Important behavior

A branch crash removes that branch and its descendants but preserves its
sibling. The input schema bounds depth before any child starts.

## Limits

This is a local ownership tree. It does not provide dynamic topology repair or
cluster authority.

## Files

- [Source](agent_hierarchy.ex)
- [Tests](../../../test/examples/05_multi_agent/05_03_agent_hierarchy/agent_hierarchy_test.exs)
- [Keep State Action](../../support/keep_state.ex)

Previous: [Correlated Requests](../05_02_correlated_requests/README.md) | Next: [Remote Child](../05_04_remote_child/README.md)
