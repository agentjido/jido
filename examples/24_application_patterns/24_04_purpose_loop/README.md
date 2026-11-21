# 24_04 Purpose Loop

One Agent continues a bounded purpose through scheduled finite Turns, then can
pause, resume, restore, and drain.

## What you will learn

- How Timer Directives continue work without a connected client.
- How generations reject stale ticks during pause, resume, and recovery.

## Read the code

Read [the Agent and state rules](purpose_loop.ex), then [the clock and Signal builders](clock.ex).

## Run it

```sh
mix test.examples examples/24_application_patterns/24_04_purpose_loop --warnings-as-errors
```

Expected result: scheduled work reaches idle, a restored paused Agent resumes,
and drain rejects later work and cleans the Timer runtime.

## Important behavior

Every tick is one finite Agent Turn. The work budget is explicit, and a
generation plus sequence pair makes delayed duplicate ticks harmless.

## Limits

This is one local Agent with an in-memory work list. It is not a durable queue
or an endless Action loop.

## Files

- [Agent and state rules](purpose_loop.ex)
- [Clock and Signals](clock.ex)
- [Tests](purpose_loop_test.exs)

Previous: [Runtime Subscription](../24_03_runtime_subscription/README.md) |
Next: [Compensation](../24_05_compensation/README.md)
