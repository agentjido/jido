> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Signed Signal Identity

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_12_signed_signal_identity`
- **Status:** implemented
- **Complexity level:** 3 - Runtime
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Verify sender control of a private key and sign a correlated reply.
- **User story:** As a receiving Actor, I accept only authentic, fresh Signals from trusted identities.
- **Trigger or input:** A signed inbound Signal.
- **Agent state:** Trusted public keys, accepted nonce records, and last verified sender.
- **Actions or Flow:** One Action handles a Signal only after identity Plugin admission succeeds.
- **External interactions:** Cryptographic operations use local keys and deterministic fixtures.
- **Runtime Directives or capabilities:** An outbound dispatch capability signs the reply after Jido adds correlation data.
- **Expected result:** Valid Signals enter one turn. Forged and replayed Signals do not route.
- **Failure cases:** Unknown key, bad signature, replayed nonce, missing correlation, or signing error.
- **Jido features under pressure:** Admission Plugin, trace and correlation, replay protection, secrets, and outbound transform.
- **Source framework and links:** [Semantic Kernel: agent architecture and threads](https://learn.microsoft.com/en-us/semantic-kernel/frameworks/agent/agent-architecture), [Jido integration example](../../../../examples/08_applications/08_04_identity/identity.ex)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/runtime/04_12_signed_signal_identity/signed_signal_identity.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_12_signed_signal_identity/signed_signal_identity_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
