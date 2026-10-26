# Executable Continuation

A terminal Invoke selects an Action or a bounded Flow before it returns one
final Agent state candidate.

## What you will learn

- How Invoke selects the next executable.
- How the selected Action or Flow receives the same context.
- How Iterate bounds repeated work without an intermediate commit.

## Read the code

Read [the Agent and selected targets](executable_continuation.ex) first. Then
read [the behavior tests](../../../test/examples/02_workflow/02_08_executable_continuation/executable_continuation_test.exs).

## Run it

```sh
mix test test/examples/02_workflow/02_08_executable_continuation --include example --seed 0
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
- [Tests](../../../test/examples/02_workflow/02_08_executable_continuation/executable_continuation_test.exs)

Previous: [Nested Flow](../02_07_nested_flow/README.md) | Next: [Flow Directives](../02_09_flow_directives/README.md)
