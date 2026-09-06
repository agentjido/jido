> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# PDF to Audio

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_23_pdf_to_audio`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced runtime
- **Feature group:** runtime
- **Test class:** true integration

## Profile

- **Purpose:** Convert a document into a narrated audio artifact.
- **User story:** As a listener, I upload a PDF and receive chaptered audio.
- **Trigger or input:** `document.narrate` Signal with document reference and voice settings.
- **Agent state:** Document digest, sections, narration text, audio artifact IDs, and status.
- **Actions or Flow:** A Flow extracts text, creates narration, synthesizes bounded segments, and builds a manifest.
- **External interactions:** PDF converter, LLM, text-to-speech service, and media store.
- **Runtime Directives or capabilities:** A media Plugin owns artifact writes, segment lifecycle, and cleanup after commit.
- **Expected result:** The manifest covers all accepted sections and names every audio artifact.
- **Failure cases:** Unreadable PDF, unsafe text, synthesis error, size limit, missing segment, or cleanup failure.
- **Jido features under pressure:** Long Flow, media resources, partial external output, compensation, and state size.
- **Source framework and links:** [Mastra: PDF to audio example](https://mastra.ai/en/examples/pdf-to-audio), [PydanticAI: text to audio](https://pydantic.dev/docs/ai/examples/realtime/realtime-text-to-audio/)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/runtime/04_23_pdf_to_audio/pdf_to_audio.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_23_pdf_to_audio/pdf_to_audio_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: The fixture validates complete manifest coverage. Extraction, synthesis, artifact ownership, and partial-output cleanup are not implemented.

An example-scope gap is not evidence of a core Jido defect.
