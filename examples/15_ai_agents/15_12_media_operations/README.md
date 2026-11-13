# 15_12 Media Operations

A normal Flow runs image generation, OCR, speech synthesis, transcription, and
video generation through one deterministic inference client.

## What you will learn

- How media operations belong in explicit application Actions.
- How Actions select `Jido.AI.InferenceClient` from execution context.
- How a Flow composes independent media results into one typed output.

## Read the code

Read [the Flow](media_operations.ex), then the four
[media Actions](media_actions.ex).

## Run it

`mix test.examples examples/15_ai_agents/15_12_media_operations --warnings-as-errors`

Expected result: the offline client returns deterministic image, OCR, speech,
transcription, and video metadata with no file or network access.

## Important behavior

Jido core supplies the inference-client contract and normal Flow execution.
The application chooses operation order, models, storage, polling, and result
shape. Each remote operation would be an effectful Action and can repeat if an
unfinished durable step recovers.

## Limits

The outputs are small local fixtures. The lesson does not prove provider
compatibility, streaming media, upload retention, content safety, polling
backoff, billing, or idempotency at a provider.

## Core Fit and Gaps

The existing callback surface composes as ordinary Actions; no media workflow
API is required in core. Production video and file operations need explicit
operation IDs, retry policy, durable references, and cleanup in application or
adapter code.

## Files

- [Flow](media_operations.ex)
- [Actions](media_actions.ex)
- [Tests](media_operations_test.exs)
- [Offline client](../../support/offline_inference_client.ex)

Previous: [Multimodal Content](../15_11_multimodal_content/README.md) |
Next: [Skills and Tool Sources](../15_13_skills_and_tool_sources/README.md)
