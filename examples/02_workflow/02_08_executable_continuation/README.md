# Executable Continuation

A terminal Dispatch continues through Action and Flow modules before it returns
one final Agent state candidate.

## What you will learn

- How Dispatch selects the next executable.
- How Action and Flow continuations share one context and budget.
- How the continuation limit rejects a chain without an intermediate commit.

## Read the code

Read [the Agent and continuation chain](executable_continuation.ex) first. Then
read [the behavior tests](../../../test/examples/02_workflow/02_08_executable_continuation/executable_continuation_test.exs).

## Run it

```sh
mix test test/examples/02_workflow/02_08_executable_continuation --include example --seed 0
```

Expected result: the chain returns one final value, shared context reaches the
terminal result, and a small budget rejects a longer chain.

## Important behavior

`Expand` and `Add` are named because continuation results must refer to stable
executable modules. The one-use Dispatch decision stays inline and uses its
generated name.

## Limits

This example does not teach retries, background jobs, or Agent Server
cancellation.

## Files

- [Source](executable_continuation.ex)
- [Tests](../../../test/examples/02_workflow/02_08_executable_continuation/executable_continuation_test.exs)

Previous: [Nested Flow](../02_07_nested_flow/README.md) | Next: [Approval Workflow](../02_09_approval_workflow/README.md)
