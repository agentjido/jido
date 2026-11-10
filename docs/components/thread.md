---
title: Jido.Thread component
status: current
last-reviewed: 2026-11-10
---

# Jido.Thread component

Purpose: Record the Thread and Entry contracts and their design review.
Review result: All four review checks are complete (R5). Findings remain open.
Only the defect fix noted below is authorized for implementation.

## Local defect fixes — 2026-11-10

F3 is fixed locally: Entry encode validates the complete value first.
The user requested these fixes without tests. No tests were added or run.
The review findings below describe the source before these fixes. Other
recommendations remain open.

## Public contract

| Owner | Operations and contract |
| --- | --- |
| Thread creation | `schema/0`, `new/0,1`. Options: `id`, `now`, `metadata`. Creates revision zero with no entries. Invalid construction raises `ArgumentError`. |
| Thread change | `append/2` accepts one Entry, a map, a list, or nil. It returns a new Thread. Empty append returns the input. |
| Thread reads | `entry_count/1`, `last/1`, `get_entry/2`, `to_list/1`, `filter_by_kind/2`, `slice/3`. Missing last/entry returns nil. Kind filtering accepts nil Thread and returns `[]`. Slice uses inclusive sequence bounds. |
| Thread portable form | `encode/1`, `decode/1`. Type `jido.thread`, version 1. Decode returns `{:ok, thread}`, `{:error, :invalid_thread}`, or `{:error, :unsupported_version}`. Invalid encode raises. |
| Entry | `schema/0`, `new/1`, `encode/1`, `decode/1`. Creation accepts map or keyword data. Decode returns `{:ok, entry}` or `{:error, :invalid_entry}`. |
| Internal exports | Thread and Entry `validate/1`; Entry `normalize/3`. Runic identity implementations use each owner's `encode/1`. |

Thread owns append order and assigns zero-based contiguous sequence numbers.
Revision and derived `stats.entry_count` equal list length. Entry owns ID,
sequence, timestamp, kind, payload, and refs. Append replaces the supplied
sequence. It retains a supplied timestamp, even if that timestamp is earlier
than another entry. The documented chronological order is append order, not a
sort by `at`. Entry IDs are not checked for uniqueness.

Kind is a non-nil atom or a nonempty string. The map format tags atom and string
kinds separately. Atom decoding uses existing atoms only. Payload, refs, and
metadata use Term validation. They can contain portable BEAM terms that JSON
does not support. Thread reconstructs stats on decode and omits them on encode.

## Ownership, dependencies, and usage

Both files belong to Reach `value_model`. They use Joi, Id, Term, and Runic
identity. Entry is an internal value of the Thread component, not a separate
sub-component. There is no process, persistence, model schema, or context
window policy here.

Session consumes Thread creation, append, validation, and encoding. AI
Projection creates Entries, appends through Session, and reads the stored list
for model projection. AI contracts use kind filtering for attempts, outcomes,
and reviews. `get_entry/2`, `slice/3`, `last/1`, and `entry_count/1` have direct
tests; no production caller was found for those convenience reads. This does
not prove that downstream consumers do not use them.

## Duplication and Elixir design

- **F1 — Investigation, P3, high confidence:** `append/2` calls `length`, copies the
  list with `++`, then validates the complete history. Session adds another
  full validation. Repeated single-entry append has at least quadratic total
  list work. Preserve append order and complete-value output; measure a long
  conversation before choosing a queue, chunked form, or narrower validation.
- **F2 — Design decision, P3, high confidence:** `rev`, list length, and stats keep the same count in
  three fields. Stats is derived and not stored on the wire. Consider removal
  of the redundant field in a versioned API change. Do not add a cache process.
- **F3 — Defect, P2, high confidence:** Entry `encode/1` (`lib/jido/thread/entry.ex:45`) does not validate a modified struct,
  while Thread and Session encode do. It can return nonportable payload data.
  Either validate Entry encode or document a checked-value precondition.
  A temporary probe changed payload to `%{pid: self()}` and confirmed that
  encode returned the PID. Validation adds rejection for unchecked structs.
  Verify valid round-trips and invalid structs before a fix is accepted.
- Decode shares the key-collision issue in [Session F2](session.md). Thread
  also accepts an input `stats` field and ignores its value. Decide whether
  to reject this field. Constructors and append maps ignore unknown fields.
- Keep separate Entry validation and Thread sequence validation. They protect
  different invariants. Do not merge the component with AI projection.

## Coverage

Source state: HEAD `85023dd` with local changes. Primary review and a second
read-only reviewer checked the complete boundary.

| Responsibility | Traces | Result |
| --- | --- | --- |
| Entry | Creation, normalization, local-value rejection, encode/decode and identity | Source, tests and unchecked-struct probe checked. |
| Thread | Append order, sequences, revisions, stats, reads, portable boundary | Source, tests and ignored-stats probe checked. |
| Composition | Session append/validation and AI projection | Current success/error callers checked. No process ownership here. |

## Evidence, checks, and proof gaps

Reviewed both files (378 lines), all exports and protocol implementations,
Session and AI callers, unit tests, and conversation codec tests. The first
focused R5 run passed 184 tests, including Thread tests. The 14 additional conversation
tests passed. Final limits are recorded in R5.

`jido_ai.conversation.I1` covers these values under a legacy AI proof owner.
Tests cover normalization, query operations, round-trip, stats/revision
invariants, existing-atom decoding, versions, unknown fields, and local-value
rejection. Long-history performance, mixed-key collisions, ignored stats, and
modified Entry encode need direct proof before a fix. These gaps do not
prevent completion of the design review.

## Sources

- [Thread source](../../lib/jido/thread.ex)
- [Entry source](../../lib/jido/thread/entry.ex)
- [Thread tests](../../test/jido/thread_test.exs)
- [Conversation codec tests](../../test/jido/ai/conversation/conversation_codec_contract_test.exs)
- [AI Projection](../../lib/jido/ai/thread/projection.ex)
- [Conversation obligations](../../test/contracts/jido_ai/conversation.obligations.md)
- [Reach layers](../../.reach.exs)
