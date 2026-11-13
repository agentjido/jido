# 15_11 Multimodal Content

One normal AI request carries text and an image as portable content parts and
commits both sides of the exchange to the Session.

## What you will learn

- How text and image parts use one `input` value.
- How the normal ReAct path sends multimodal context to an inference client.
- How the committed Session retains the canonical content parts.

## Read the code

Read [the AI Agent and request builder](multimodal_agent.ex), then the Session
projection assertions.

## Run it

`mix test.examples examples/15_ai_agents/15_11_multimodal_content --warnings-as-errors`

Expected result: the offline response completes and the Session contains one
text part and one PNG image URL part in the user message.

## Important behavior

The Signal contains portable content data. This offline fixture uses a data URL.
Provider selection and capability checks remain explicit application
decisions. The deterministic inference client returns text and makes no
network request.

## Limits

The data URL contains only a PNG header, not a decoded image. The lesson proves
data shape and Jido Flow behavior, not provider image understanding, upload
limits, virus scanning, object storage, or content authorization.

## Core Fit and Gaps

The existing AI request and Session contracts preserve portable content parts
without a separate multimodal runtime. Raw binary content does not fit the
JSON-backed Session message contract. Media storage, durable references,
authorization, size limits, and model compatibility remain application
concerns.

## Files

- [Source](multimodal_agent.ex)
- [Tests](multimodal_agent_test.exs)
- [Offline client](../../support/offline_inference_client.ex)

Previous: [Capability Preflight](../15_10_capability_preflight/README.md) |
Next: [Media Operations](../15_12_media_operations/README.md)
