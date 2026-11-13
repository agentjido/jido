# 15_10 Capability Preflight

An application-owned model profile blocks an incompatible request before one
offline inference call.

## What you will learn

- How to express model requirements as normal Flow input.
- How a validation Action prevents later model work.
- Why provider capability metadata and fallback compatibility need an
  application policy.

## Read the code

Read [the preflight Flow and Actions](capability_preflight.ex), then the passing
and failing cases.

## Run it

`mix test.examples examples/15_ai_agents/15_10_capability_preflight --warnings-as-errors`

Expected result: a text-and-image profile reaches the offline model. A
text-only profile fails before inference.

## Important behavior

The application owns the profile used for selection. The selected
`Jido.AI.InferenceClient` owns execution. This lesson does not assume that one
provider capability vocabulary applies to every provider.

## Limits

The profile is a local fixture. It does not refresh a provider catalog or prove
that a live model still matches its published capabilities.

## Core Fit and Gaps

Normal Actions and Flow dependencies provide a clear preflight boundary. Jido
core does not expose one canonical cross-provider model-capability API. That is
currently an application or model-catalog concern.

## Files

- [Flow](capability_preflight.ex)
- [Actions](capability_actions.ex)
- [Tests](capability_preflight_test.exs)

Previous: [JSON Agent](../15_09_json_agent/README.md) |
Next: [Multimodal Content](../15_11_multimodal_content/README.md)
