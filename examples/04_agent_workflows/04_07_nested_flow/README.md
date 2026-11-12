# Nested Flow

A parent Flow runs the same typed child Flow twice and commits only the final
result.

## What you will learn

- How reusable child Flows keep separate result scopes.
- How caller context reaches nested Flows.
- How parent and child schemas fail at their own boundaries.

## Read the code

Read [the Agent, child Flow, and parent Flow](nested_flow.ex) first. Then read
[the behavior tests](nested_flow_test.exs).

## Run it

```sh
mix test.examples examples/04_agent_workflows/04_07_nested_flow
```

Expected result: writer and editor results stay separate, context is shared,
and invalid parent or child input does not commit.

## Important behavior

The child operation is used only inside the child Flow, so it is inline and has
no explicit name. The parent uses the child module twice because the child Flow
is the reusable contract.

## Limits

The `request` context value is a small context-propagation example. It is not a
trace or persistence contract.

## Files

- [Source](nested_flow.ex)
- [Tests](nested_flow_test.exs)

Previous: [Bounded Iteration](../04_06_bounded_iteration/README.md) | Next: [Executable Continuation](../04_08_executable_continuation/README.md)
