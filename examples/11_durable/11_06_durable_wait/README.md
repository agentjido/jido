# 11_06 Durable Wait

An approval wait survives hibernation without a blocked Action or active Turn.

## What you will learn

- Store a wait and its absolute deadline in Agent state.
- Complete the request Flow before a later approval Flow begins.
- Reject conflicting and duplicate decisions.

## Read the code

Read [the Agent and two Flows](durable_wait.ex). `request_signal/1` supplies a
stable request ID and an absolute Unix deadline in milliseconds.
`resolve_signal/1` supplies that ID and `decision: :approve` or `:cancel`.

## Important behavior

The request Flow commits `:waiting` and releases the Turn. Hibernation saves
that state. After thaw, a matching decision becomes `:approved` or `:cancelled`.
An elapsed deadline becomes `:expired`. The deadline is not reset on restore.
A second decision or a different request ID returns an error.

The tests restore pending, expired, and cancelled requests. They also prove
that duplicate approval cannot change the completed request.

## Limits

There is no suspended Flow or durable mailbox. The wait is data between Turns.
Expiry is evaluated when a decision arrives; no timer sends a decision. The
application owns delivery, authorization, and clock policy. `Server.cancel/1`
cancels execution, not this stored domain request; use the resolve route.

## Run it

```sh
mix test test/examples/11_durable/11_06_durable_wait --include example --seed 0 --warnings-as-errors
```

Expected result: the success, recovery, and rejection assertions pass. Tests stop
the Agents and release all held test calls. No external service is required.

## Files

- [Source](durable_wait.ex)
- [Tests](../../../test/examples/11_durable/11_06_durable_wait/durable_wait_test.exs)

Previous: [Saved Completion](../11_05_saved_completion/README.md) | Next: [External Uncertainty](../11_07_external_uncertainty/README.md)
