> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Lead Qualification

- **ID:** `02_05_lead_qualification`
- **Status:** archived research profile
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Score a lead and route it by clear business rules.
- **User story:** As a sales team, I receive a qualified lead record and the correct next step.
- **Trigger or input:** `lead.received` Signal from a form, Slack, or fixture.
- **Agent state:** Lead fields, evidence, score, route, approval state, and CRM record ID.
- **Actions or Flow:** A Flow validates, enriches, scores, requests review when needed, and chooses a route.
- **External interactions:** Enrichment and CRM adapters. Local tests use fixed fixtures.
- **Runtime Directives or capabilities:** A Plugin Directive can create the CRM record after commit. Human review needs the approval contract.
- **Expected result:** Each lead has an explainable score and one terminal route.
- **Failure cases:** Missing contact, enrichment error, score tie, CRM duplicate, or review timeout.
- **Jido features under pressure:** Flow branching, external writes, idempotency, approval boundary, and correlation.
- **Source framework and links:** [CrewAI: lead score Flow](https://github.com/crewAIInc/crewAI-examples/tree/main/flows/lead-score-flow), [PydanticAI: Slack lead qualifier](https://pydantic.dev/docs/ai/examples/slack-lead-qualifier/)

## Burn-in result

The local example passes. Validation, enrichment, scoring, and Choice routing
produce one explainable state. A review request is ordinary pending domain
state. The example does not invent a suspend mechanism or write to a CRM.

## Best-effort implementation

- Code history: `git show ee1e641:examples/02_workflow/02_05_lead_qualification/lead_qualification.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_05_lead_qualification/lead_qualification_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
