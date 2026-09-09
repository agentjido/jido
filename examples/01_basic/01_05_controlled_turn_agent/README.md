# Controlled Turn Agent

This example makes Action execution observable and controllable. It teaches
serial Turns, queued caller context, cancellation, worker cleanup, and caller
timeouts.

## Read the files

1. Read [the Agent](controlled_turn_agent.ex).
2. Read [the behavior tests](../../../test/examples/01_basic/01_05_controlled_turn_agent/controlled_turn_agent_test.exs).
3. Read [the shared test case](../../../test/examples/support/basic_sdk_case.ex) for the isolated runtime setup.

## Run the example

Run this command from the `jido` repository root:

```sh
mix test test/examples/01_basic/01_05_controlled_turn_agent/controlled_turn_agent_test.exs --include example --seed 0
```

Queued work starts only after the active Turn commits and receives its own
caller context. Cancellation stops the active worker without a commit and then
allows queued work to run. A caller timeout stops only the wait; it does not
cancel work that already started.

Tests use explicit worker messages, server-status barriers, and process monitors.
Observer PIDs and the `blocked?` control stay in transient execution context.
Cancellation confirms worker cleanup. The isolated Jido instance stops the
remaining processes after each test.

The barrier is deterministic test scaffolding. It is not an application
coordination protocol. This example does not teach persistence, remote work, or
durable cancellation.

[Previous: Directive Agent](../01_04_directive_agent/README.md) · [Back to Basic](../README.md) · [Next: Workflow examples](../../02_workflow/README.md)
