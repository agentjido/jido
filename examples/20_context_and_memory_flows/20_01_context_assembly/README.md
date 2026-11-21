# 20_01 Context assembly

This Flow projects static instructions, request input, Agent state, Session
state, resource data, and tenant policy into one ordered model context.

## What you will learn

- How to keep open application data separate from a prepared model projection.
- How to name the owner and provenance of every context layer.
- How to make a context transform idempotent and digestible.

## Read the code

Read [the projection Action and Flow](context_assembly.ex) first.

## Run it

`mix test.examples examples/20_context_and_memory_flows/20_01_context_assembly --warnings-as-errors`

Expected result: six layers have a stable order, owner, digest, byte count, and
cache observation. Running the same projection twice returns the same value.

## Important behavior

The Flow copies only declared fields. It does not put full Agent state,
Session history, resource documents, or tenant records into the prompt. Prompt
cache data is an observation. It does not compact or delete Session history.

## Limits

The byte count is not a provider token count. The example does not call a model
or prove that one provider will cache the prompt.

## Core Fit and Gaps

Action validation and Flow ordering are sufficient for application-owned
context projection. Jido does not need a hidden context middleware API. The
application remains responsible for field-level authorization and token
estimation.

## Files

- [Source](context_assembly.ex)
- [Tests](context_assembly_test.exs)

[Next: Trim and compact](../20_02_trim_and_compact/README.md)
