# 05_05 Custom Directives and post-commit hooks

Let one Plugin validate a custom effect request and observe the completed
commit before it dispatches that effect.

## What you will learn

- A Plugin declares and owns each custom Directive type that it can dispatch.
- `after_commit/3` receives only the Plugin-owned committed value and revision.
- AgentServer runs commit hooks before Directive dispatch.

## Read the code

Read [the notifier Plugin](commit_notifier.ex) first.

## Run it

`mix test.examples examples/05_plugins/05_05_directives_and_hooks --warnings-as-errors`

Expected result: revision 1 contains the message and notification count. The
commit hook runs before the custom notification dispatch.

## Important behavior

The Agent owns domain state. The Plugin owns `notifications`, Directive
validation, the post-commit hook, and dispatch. The process owner is
AgentServer. Invalid Directives fail before commit. A hook or dispatch failure
after commit cannot roll state back.

## Limits

Hooks and Directives are not replayed automatically. The observer PID is
transient AgentServer configuration. It is not stored in Agent state.

## Core Fit and Gaps

Plugin state reduction, post-commit notification, and custom Directive
dispatch compose in one public Plugin contract. An application that needs
recoverable effect delivery must store an intent and use an explicit retry or
outbox boundary.

## Files

- [Source](commit_notifier.ex)
- [Tests](commit_notifier_test.exs)

Previous: [State reduction](../05_04_state_reduction/README.md) | Next: [Supervised runtime](../05_06_supervised_runtime/README.md)
