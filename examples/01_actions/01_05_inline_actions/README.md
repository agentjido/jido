# 01_05 Inline Actions

One small host DSL compiles owner-scoped code to a normal validated Action
target.

## What you will learn

- How `Jido.Action.Inline` keeps one-use code with its owner.
- How the generated target still runs through `Jido.Exec`.

## Read the code

Read [the host and owner](inline_actions.ex), then read
[the tests](inline_actions_test.exs).

## Run it

`mix test.examples examples/01_actions/01_05_inline_actions --warnings-as-errors`

Expected result: the inline Action returns `Hello Ada` and rejects an empty
name.

## Important behavior

The source body is compile-time code owned by `Greeting`. Stored or runtime
code is not accepted.

## Limits

Generated module names are implementation details. The typed host path is the
declaration identity, not a code version.

## Core Fit and Gaps

The generated target uses normal Action validation and execution. A host must
still define both the three-argument declaration macro and the four-argument
form used by a declaration with a `do` block. This is public extension code,
not a core gap. The [inline host guide](../../../guides/flows/building-dsls-with-inline-actions.md#build-a-callback-host)
shows both arities and explains how Elixir selects them.

## Files

- [Host and owner](inline_actions.ex)
- [Tests](inline_actions_test.exs)
