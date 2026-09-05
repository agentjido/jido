> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Secure Signal Envelope

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_09_secure_signal_envelope`
- **Status:** implemented
- **Complexity level:** 3 - Runtime
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Verify and decrypt protected Signal data before Action execution.
- **User story:** As a user, I send secure data that stays out of logs and committed plaintext state.
- **Trigger or input:** An encrypted and signed inbound Signal.
- **Agent state:** Only allowed derived values, sender identity, and acceptance result.
- **Actions or Flow:** One Action receives transient decrypted context and returns safe domain state.
- **External interactions:** Local cryptographic fixtures.
- **Runtime Directives or capabilities:** Input capabilities verify then decrypt. Outbound capabilities encrypt before identity signing.
- **Expected result:** Valid secure data is processed, and plaintext does not enter durable state or telemetry.
- **Failure cases:** Bad signature, wrong key, replay, decrypt failure, unsafe state output, or encryption error.
- **Jido features under pressure:** Plugin order, transient context, sensitive data, output filtering, and secure dispatch.
- **Source framework and links:** [CrewAI: MCP security considerations](https://docs.crewai.com/en/mcp/security), [Jido integration example](../../../../test/integration/secure_signal/example_test.exs)

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/runtime/04_09_secure_signal_envelope/secure_signal_envelope.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_09_secure_signal_envelope/secure_signal_envelope_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
