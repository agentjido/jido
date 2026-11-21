# 04_05 Replies and Directives

An Agent commits new state and then sends an ordered Directive batch to its
Plugin runtime.

## What you will learn

- How whole-batch Directive validation protects a commit.
- How Plugin effects run after a successful commit.
- How dispatch order, dispatch failure, and Plugin cleanup work.

## Read the code

Read [the Agent](directive_agent.ex) first. Then read
[the Directive, Effects Plugin, and Plugin runtime](effects.ex), followed by
[the behavior tests](directive_agent_test.exs).

## Run it

Run this command from the `jido` repository root:

```sh
mix test.examples examples/04_agents/04_05_replies_and_directives --warnings-as-errors
```

Expected result: the tests complete without failures. A valid batch runs in
order after commit, while an invalid Directive prevents dispatch.

## Important behavior

An invalid Directive prevents the complete commit and all dispatch. A dispatch
failure happens after commit, does not undo that commit, and prevents later
Directives in the batch. Stopping the Agent Server also stops its Plugin runtime.
The host application supervises the Registry that addresses that runtime.

## Limits

The recording Plugin is a deterministic local adapter. It does not prove remote
delivery, retry, idempotency, or durable effect recovery.

## Files

- [Agent source](directive_agent.ex)
- [Directive, Plugin, and runtime](effects.ex)
- [Behavior tests](directive_agent_test.exs)
Previous: [Pure Execution](../04_04_pure_execution/README.md) | Next: [Agent Callbacks](../04_06_agent_callbacks/README.md)
