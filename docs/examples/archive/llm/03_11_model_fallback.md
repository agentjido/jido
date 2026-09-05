> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Model Fallback

- **ID:** `03_11_model_fallback`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Select a backup model only for approved failure classes.
- **User story:** As an operator, I keep a user request working when the primary model has a transient fault.
- **Trigger or input:** Any model-backed request with a model route policy.
- **Agent state:** Requested capability, model attempts, selected model, usage, warnings, and result.
- **Actions or Flow:** A Flow calls the primary model and conditionally calls a compatible backup.
- **External interactions:** Two model providers. Local tests use fake adapters with fixed failures.
- **Runtime Directives or capabilities:** None for synchronous calls. A managed provider pool can be a Plugin capability.
- **Expected result:** The result identifies the model route and preserves compatible output shape.
- **Failure cases:** Auth error, incompatible tool support, both models fail, budget limit, or unsafe fallback.
- **Jido features under pressure:** Error classification, provider abstraction, output compatibility, budgets, and observability.
- **Source framework and links:** [Pi: unified multi-provider LLM API](https://github.com/earendil-works/pi/tree/main/packages/ai), [PydanticAI: model providers](https://pydantic.dev/docs/ai/models/overview/)

## Best-effort implementation

- `git show 357b22a:lib/examples/03_llm/03_11_model_fallback/model_fallback.ex`
- `git show 357b22a:test/examples/03_llm/03_11_model_fallback/model_fallback_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
