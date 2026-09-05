> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Typed Bank Support

- **ID:** `02_15_typed_bank_support`
- **Status:** archived research profile
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Give a customer a typed answer based on account data and policy.
- **User story:** As a bank customer, I ask about my balance or recent transactions and receive a safe answer.
- **Trigger or input:** `support.bank.question` Signal with customer ID and question.
- **Agent state:** Verified customer context, intent, safe result, and escalation status.
- **Actions or Flow:** A Flow loads account data, classifies intent, applies policy, and builds typed output.
- **External interactions:** Account service and optional model. Local tests use fake customer records and replies.
- **Runtime Directives or capabilities:** An `Emit` can send an escalation Signal after commit. Sensitive data must not enter Directive metadata.
- **Expected result:** The answer is grounded in allowed records or the case is escalated.
- **Failure cases:** Customer not found, auth failure, policy refusal, provider timeout, or invalid output.
- **Jido features under pressure:** Typed dependencies, sensitive state, external reads, escalation, and structured refusal.
- **Source framework and links:** [PydanticAI: bank support](https://pydantic.dev/docs/ai/examples/conversational-agents/bank-support/)

## Burn-in result

The local example passes. Account data and authorization stay inside Flow
execution. Actor state keeps only the verified customer reference and allowed
answer fields. Unsupported questions become explicit escalation state.

## Best-effort implementation

- Code history: `git show ee1e641:lib/examples/02_workflow/02_15_typed_bank_support/typed_bank_support.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_15_typed_bank_support/typed_bank_support_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
