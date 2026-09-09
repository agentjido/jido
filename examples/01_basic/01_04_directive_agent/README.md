# Directive Agent

This example changes Agent state and emits a batch of Directives. It teaches
whole-batch validation, commit-before-effect order, ordered dispatch, dispatch
failure, and Plugin runtime cleanup.

## Read the files

1. Read [the Agent](directive_agent.ex).
2. Read [the Directive, Effects Plugin, and Plugin runtime](effects.ex).
3. Read [the behavior tests](../../../test/examples/01_basic/01_04_directive_agent/directive_agent_test.exs).
4. Read [the shared test case](../../../test/examples/support/basic_sdk_case.ex) for the isolated runtime setup.

## Run the example

Run this command from the `jido` repository root:

```sh
mix test test/examples/01_basic/01_04_directive_agent/directive_agent_test.exs --include example --seed 0
```

For a valid batch, the Agent commits once and the Plugin handles all three
Directives in list order. Each handler reads the committed snapshot.

An invalid Directive prevents the complete commit and all dispatch. A dispatch
failure happens after commit, does not undo the commit, and prevents later
Directives in that batch. The cleanup assertion stops the Agent Server and
confirms that its Plugin runtime also stops.

The recording Plugin is a deterministic local adapter. It does not prove remote
delivery, retry, idempotency, or durable effect recovery.

[Previous: Plugin State Agent](../01_03_plugin_state_agent/README.md) · [Back to Basic](../README.md) · [Next: Controlled Turn Agent](../01_05_controlled_turn_agent/README.md)
