# 20_02 Trim and compact

This Flow keeps the newest history within message and byte budgets, then sends
only dropped messages to an offline compaction Action.

## What you will learn

- How deterministic history trimming differs from lossy model compaction.
- How message, byte, estimated-token, and model-call budgets stay explicit.
- Why a context window does not delete full Session history.

## Read the code

Read [the trimming and compaction Actions](trim_and_compact.ex), then read the
[offline inference client](../../support/offline_inference_client.ex).

## Run it

`mix test.examples examples/20_context_and_memory_flows/20_02_trim_and_compact --warnings-as-errors`

Expected result: the newest messages remain verbatim, dropped messages produce
one fixed summary, and the original history stays unchanged.

## Important behavior

Trimming is deterministic and can be replayed from recorded input. Compaction
is lossy model work. The result records the count of source messages and model
calls. A production application must store the full history and compaction
provenance separately.

## Limits

The token estimate uses four bytes per token and is not a provider count. The
fixture summary does not prove factual preservation. Time and cost bounds are
policy inputs for a real client, not measured by this local fixture.

## Core Fit and Gaps

Normal Actions and Flow references keep deterministic and model-assisted work
separate. The inference-client compaction callback is sufficient. Jido does not
own automatic Session compaction or deletion policy.

## Files

- [Source](trim_and_compact.ex)
- [Tests](trim_and_compact_test.exs)
- [Offline client](../../support/offline_inference_client.ex)

[Previous: Context assembly](../20_01_context_assembly/README.md)

[Next: Working memory and recall](../20_03_working_memory_and_recall/README.md)
