# Executable Continuation

A terminal Invoke selects an Action or a bounded Flow before it returns one
final Agent state candidate.

## What you will learn

- How Invoke selects the next executable.
- How the selected Action or Flow receives the same context.
- How Iterate bounds repeated work without an intermediate commit.

## Read the code

Read [the Agent and selected targets](executable_continuation.ex) first. Then
read [the behavior tests](executable_continuation_test.exs).

## Run it

```sh
mix test.examples examples/03_flow_execution/03_24_executable_continuation
```

Expected result: Invoke selects `Finish` when no additions remain. Otherwise,
it selects `Repeat`, which permits at most three additions. Both targets return
one final value with the caller context.

## Important behavior

Only the Invoke expander returns a continuation. The selected Actions return
normal results. The selected Flow uses Iterate for repetition. If four or more
additions are requested, it fails at the iteration limit and preserves the
previous Agent state. No `max_continuations` execution option is used.

## Limits

This example does not teach retries, background jobs, or Agent Server
cancellation.

## Files

- [Source](executable_continuation.ex)
- [Tests](executable_continuation_test.exs)

Previous: [Nested Flow](../03_23_nested_flow/README.md) | Next: [Flow Directives](../03_25_flow_directives/README.md)
