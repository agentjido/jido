# Directive Agent

An Agent commits new state and then sends an ordered Directive batch to its
Plugin runtime.

## What you will learn

- How whole-batch Directive validation protects a commit.
- How Plugin effects run after a successful commit.
- How dispatch order, dispatch failure, and Plugin cleanup work.

## Read the code

Read [the Agent](directive_agent.ex) first. Then read
[the Directive, Effects Plugin, and Plugin runtime](effects.ex), followed by
[the behavior tests](../../../test/examples/01_basic/01_04_directive_agent/directive_agent_test.exs).

## Run it

Run this command from the `jido` repository root:

```sh
mix test test/examples/01_basic/01_04_directive_agent/directive_agent_test.exs --include example --seed 0
```

Expected result: the tests complete without failures. A valid batch runs in
order after commit, while an invalid Directive prevents dispatch.

## Important behavior

An invalid Directive prevents the complete commit and all dispatch. A dispatch
failure happens after commit, does not undo that commit, and prevents later
Directives in the batch. Stopping the Agent Server also stops its Plugin runtime.

## Limits

The recording Plugin is a deterministic local adapter. It does not prove remote
delivery, retry, idempotency, or durable effect recovery.

## Files

- [Agent source](directive_agent.ex)
- [Directive, Plugin, and runtime](effects.ex)
- [Behavior tests](../../../test/examples/01_basic/01_04_directive_agent/directive_agent_test.exs)
- [Shared test setup](../../../test/examples/support/basic_sdk_case.ex)

Previous: [Plugin State Agent](../01_03_plugin_state_agent/README.md) | Next: [Workflow examples](../../02_workflow/README.md)
