> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Learning Guide Creator

- **ID:** `02_06_learning_guide_creator`
- **Status:** archived research profile
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Build a structured guide through planning, writing, review, and assembly.
- **User story:** As a learner, I request a guide for a topic and audience level.
- **Trigger or input:** `guide.create` Signal with topic, audience, and section limit.
- **Agent state:** Outline, completed sections, review notes, final document, and status.
- **Actions or Flow:** A Flow creates an outline, writes each section, reviews it, and compiles the guide.
- **External interactions:** Model calls and optional file write. Local tests use fixed model replies and an in-memory file adapter.
- **Runtime Directives or capabilities:** A Dispatch Plugin Directive can save or publish the final guide after commit.
- **Expected result:** A complete ordered guide commits once with traceable section outputs.
- **Failure cases:** Invalid outline, section failure, review rejection, size limit, or publish error.
- **Jido features under pressure:** Long Flow, bounded iteration, effectful steps, state size, and one terminal commit.
- **Source framework and links:** [CrewAI: build your first Flow](https://docs.crewai.com/en/guides/flows/first-flow)

## Burn-in result

The local example passes. An outline step feeds ordered Map components for
writing and review. One rejected section fails the Flow, and no partial guide
enters Actor state.

## Best-effort implementation

- Code history: `git show ee1e641:examples/02_workflow/02_06_learning_guide_creator/learning_guide_creator.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_06_learning_guide_creator/learning_guide_creator_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
