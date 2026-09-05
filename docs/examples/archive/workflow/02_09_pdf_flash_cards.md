> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# PDF Flash Cards

- **ID:** `02_09_pdf_flash_cards`
- **Status:** archived research profile
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Turn a document into verified study cards.
- **User story:** As a learner, I upload a PDF and receive question and answer cards tied to pages.
- **Trigger or input:** `study.cards.create` Signal with document ID and card count.
- **Agent state:** Document digest, extracted sections, cards, page citations, and quality warnings.
- **Actions or Flow:** A Flow extracts text, segments it, creates cards, and checks citation coverage.
- **External interactions:** PDF converter and model. Local tests use extracted-text fixtures and fake model output.
- **Runtime Directives or capabilities:** A Dispatch Plugin Directive can save the card deck after commit.
- **Expected result:** Each card has a question, answer, and valid source page.
- **Failure cases:** Unreadable PDF, empty page, model error, duplicate card, or bad page citation.
- **Jido features under pressure:** Document adapters, batch bounds, provenance, structured output, and state size.
- **Source framework and links:** [Mastra: Flash Cards from PDF template](https://mastra.ai/docs)

## Burn-in result

The local example passes. Injected extraction and model adapters feed page
segmentation and a final citation check. A card with an unknown page prevents
the deck commit.

## Best-effort implementation

- Code history: `git show ee1e641:lib/examples/02_workflow/02_09_pdf_flash_cards/pdf_flash_cards.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_09_pdf_flash_cards/pdf_flash_cards_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
