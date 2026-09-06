> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Marketing Strategy

- **ID:** `03_10_marketing_strategy`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Combine market research, positioning, channel choice, and content ideas.
- **User story:** As a product marketer, I receive a strategy that traces each claim to input evidence.
- **Trigger or input:** `marketing.plan` Signal with product brief, audience, budget, and source pack.
- **Agent state:** Brief, evidence, segments, positioning, channels, content plan, and risks.
- **Actions or Flow:** A Flow runs specialist analysis stages and a final consistency check.
- **External interactions:** Optional search and model calls. Local tests use a fixed research pack.
- **Runtime Directives or capabilities:** An `Emit` can send approved content tasks after commit.
- **Expected result:** The strategy respects budget and uses only cited evidence.
- **Failure cases:** Missing brief, unsupported claim, budget mismatch, stage error, or inconsistent output.
- **Jido features under pressure:** Multi-stage Flow, large typed output, evidence links, and downstream Signals.
- **Source framework and links:** [CrewAI: marketing strategy crew](https://github.com/crewAIInc/crewAI-examples/tree/main/crews/marketing_strategy)

## Best-effort implementation

- `git show 357b22a:examples/03_llm/03_10_marketing_strategy/marketing_strategy.ex`
- `git show 357b22a:test/examples/03_llm/03_10_marketing_strategy/marketing_strategy_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
