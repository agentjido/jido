# 05_06 Supervised Plugin runtime

Start one activation-local Plugin runtime and clean up its resource with the
owning Agent process tree.

## What you will learn

- `child_spec/1` starts a permanent Plugin runtime root under AgentServer.
- `Jido.Plugin.Init` supplies identity, committed Plugin state, and revision.
- `await_ready/2` blocks Agent admission until the runtime can serve work.
- A custom Directive contacts the runtime only after commit.

## Read the code

Read [the runtime resource Plugin](runtime_resource.ex) first.

## Run it

`mix test.examples examples/05_plugins/05_06_supervised_runtime --warnings-as-errors`

Expected result: the runtime reports revision 0 startup data after Agent
revision 1 commits. Stopping the Agent stops the AgentServer, Plugin runtime,
and linked resource.

## Important behavior

The logical owner is the Agent. AgentServer is the process owner. The Plugin
owns its runtime root and linked resource. The Agent remains the canonical
state owner; runtime state is activation-local and disposable.

## Limits

This lesson proves startup readiness and shutdown cleanup. It does not claim
that an activation-local resource is durable or that its live handle survives
runtime replacement. A replacement runtime must rebuild from `Jido.Plugin.Init`.

## Core Fit and Gaps

Plugin child specifications, readiness, custom Directive dispatch, and OTP
cleanup compose through public contracts. The runtime handle does not enter
Agent state. Applications must rebuild external subscriptions or clients from
committed Plugin state after replacement.

## Files

- [Source](runtime_resource.ex)
- [Tests](runtime_resource_test.exs)

Previous: [Directives and hooks](../05_05_directives_and_hooks/README.md) | Next: [Plugin DSL](../05_07_plugin_dsl/README.md)
