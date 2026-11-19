---
title: Jido.Thread component
status: current
last-reviewed: 2026-11-19
---

# Jido.Thread component

Purpose: Record the Thread and Entry contracts and their design review.
## Release review for 2026-11-19

Reviewed [`6fdc009a1edd6261f3e26509fa2905bb9192faa5`](https://github.com/agentjido/jido/commit/6fdc009a1edd6261f3e26509fa2905bb9192faa5) from `origin/release/v3`. All four checks in [the component map](../../components.md#component-review-checklist) have evidence. The review is part of [#453](https://github.com/agentjido/jido/issues/453).

### Public surface

| Surface | Contract |
| --- | --- |
| Construction | `Thread.new/0,1` creates a Thread with an optional `id`, `now`, and `metadata`. `Entry.new/1` accepts a map or keyword list and gives omitted fields their defaults. Invalid field values can raise `ArgumentError`. |
| Append and reads | `append/2` accepts one Entry or map, a list of them, or nil. Nil and an empty list return the original value. The Thread assigns contiguous sequences from zero. Its revision and stats count the entries. `updated_at` is nondecreasing. Supplied Entry timestamps can go backward. `to_list/1`, `filter_by_kind/2`, and inclusive `slice/3` use append order. `last/1` and `get_entry/2` return nil for missing entries. A nil Thread gives an empty kind filter result. |
| Portable maps | Thread encode writes `jido.thread` version 1. Entry encode tags atom and string kinds. Thread decode rebuilds stats, and both decoders accept struct or map input. Thread decode returns `{:ok, thread}`, `{:error, :invalid_thread}`, or `{:error, :unsupported_version}`. Entry decode returns `{:ok, entry}` or `{:error, :invalid_entry}`. Atom tags require an existing atom. Payload, refs, and metadata use the BEAM storage policy in `Jido.Codec.Term`. |
| Validation and identity | `schema/0` in both modules exposes the Joi shape. The full validators also check domain and portability rules. `Entry.normalize/3` is Thread's internal builder for append. Both Runic identity implementations return their encode documents. |

### Callers and test evidence

- Session calls Thread construction, append, encode, decode, and full validation. Its revision can exceed the Thread revision after a metadata or lifecycle change. The nested Thread codec determines whether Session can read its history. [Session](../../lib/jido/session.ex)
- AI projection builds Entries and appends through Session. Projection and the final Turn response read the stored list in sequence order. The final response encodes the new entries with `Entry.encode/1`. The AI review of projection rules is separate. [Projection](../../lib/jido/ai/thread/projection.ex) · [FinalizeTurn](../../lib/jido/ai/reasoning/actions/finalize_turn.ex)
- Production uses the value fields and encoding operations. The public `last/1`, `get_entry/2`, and `slice/3` reads have test or example callers. The review found no use of those reads in `lib/`. The examples cover immutable updates, JSON round trips, and restored Agent state. [Thread tests](../../test/jido/thread_test.exs) · [Codec tests](../../test/jido/ai/conversation/conversation_codec_contract_test.exs) · [Conversation examples](../../examples/19_sessions_and_conversations)
- On Elixir 1.18.4 and OTP 27.3, the focused Thread, Session, conversation, AI Turn, and ReAct runtime suites passed 74 tests. The offline conversation examples passed 11 tests. `mix format --check-formatted` passed.

### Elixir and OTP design

Thread and Entry form one immutable component in Reach `value_model`. Session owns lifecycle and uses Thread in one direction. AI consumes the ordered history. AgentServer and Persistence own runtime and storage. Keep the list, the version 1 form, and the current public struct fields for this release. The list supports an ordered read without a copy. Append copies the existing list prefix. A queue or a different representation needs a separate compatibility decision.

The Joi shape and domain checks have different roles. A probe showed that Joi accepts a Thread with a wrong revision, while the full validator returns `{:error, :invalid_thread}`. Keep domain checks at the value boundary. The review covers Entry with Thread and checks how AI projection uses the history. At the review commit, `jido_ai.conversation` covered Session, Thread, and projection. [Reach layers](../../.reach.exs) · [Conversation decisions](../../test/contracts/jido_ai/conversation.decisions.yml)

### Defects

- **P2. Preserve explicit values when applying defaults.** Entry decode preserved a false atom kind. Append replaced it with `:note`. Wrong-type false values in defaulted portable fields also passed as omitted. Keep the documented defaults for missing and nil values. Consolidate the repeated Entry builder defaults while preserving the sequence and timestamp rules. [#503](https://github.com/agentjido/jido/issues/503)
- **P2. Reject ambiguous and malformed portable records.** Competing atom and string keys removed an entry from a Thread and the Session decoder accepted the changed history. Improper entries lists raised in map and struct decode. A partial Thread marker raised `KeyError`. Return the existing invalid-value tags for these shapes. Keep the version and existing valid map forms. [#505](https://github.com/agentjido/jido/issues/505)
- **P3. Use the Thread sequence in AI callers.** A valid stored Session with two entries sharing an ID returned one projected message but marked both entries as included. Use the unique sequence for membership and keep the ID in results. Document append order and use the ordered accessor in the affected callers. Preserve message choices and the response entry order. [#507](https://github.com/agentjido/jido/issues/507)

### Behavior-preserving cleanup

- **P3. Reduce repeated Thread validation.** Append, encode, and decode repeat Entry checks and list traversal. At 1,000 and 5,000 entries, one append used 10.7 million and 53.1 million BEAM reductions. Encode used 18.9 million and 94.3 million. Each sample starts from a prebuilt Thread with fixed one-key payload and ref maps. The probe takes the median of five per-process reduction counts. Re-run it after a fix. Compare reductions and preserve struct invariants, validation errors, the portable maps, and Runic identity. [#509](https://github.com/agentjido/jido/issues/509)

The earlier unchecked Entry encode defect was fixed at this commit. A modified Entry with a PID in its payload raised `ArgumentError`. The probe also confirmed that decode rebuilds stats and accepts a missing revision and nil metadata. Keep compatibility for those version 1 inputs.

## Implementation and proof

- Entry construction and append share the same defaults. The atom `false`
  stays a kind. In fields that require another type, validation rejects it.
  [#503](https://github.com/agentjido/jido/issues/503)
- The Thread and Entry decoders reject competing atom and string field
  names. The Thread decoder returns an error tuple for malformed entry
  lists and incomplete Thread structs. The version check still reports
  unsupported document types and versions.
  [#505](https://github.com/agentjido/jido/issues/505)
- AI projection identifies entries by sequence. The output keeps each
  original ID. Projection and the final Turn response read through
  `Thread.to_list/1` in append order.
  [#507](https://github.com/agentjido/jido/issues/507)
- Each Thread operation checks entry contents once. A single history scan
  checks order and counts entries. The same Joi schema checks the remaining
  Thread fields. The public value shape and version 1 output stay compatible.
  [#509](https://github.com/agentjido/jido/issues/509)

### Reduction measurements

Each value is the median of five runs on Elixir 1.18.4 and OTP 27.3 with
four schedulers. Each append adds one Entry to a prebuilt Thread. Each
entry has one payload field and one ref field.

| Operation | Stored entries | Before, millions | After, millions |
| --- | ---: | ---: | ---: |
| Thread append | 1,000 | 10.69 | 8.27 |
| Thread append | 5,000 | 53.13 | 41.16 |
| Thread encode | 1,000 | 18.93 | 8.26 |
| Thread encode | 5,000 | 94.29 | 41.19 |

### Covenant ownership

`jido.thread` owns the append order and portable format proof for Thread and
Entry. A narrow Covenant run passed both obligations across 10 tests. Session
revision and AI projection keep their current proof in
`jido_ai.conversation`. Their separate ownership decisions remain open.
[ADR 0012](../adr/0012-thread-proof-ownership.md) · [Thread obligations](../../test/contracts/jido/thread.obligations.md)

## Review history for 2026-11-10

### Local defect fixes — 2026-11-10

F3 is fixed locally: Entry encode validates the complete value first.
The user requested these fixes without tests. No tests were added or run.
The review findings below describe the source before these fixes. Other
recommendations remain open.

### Public contract

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

### Ownership, dependencies, and usage

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

### Duplication and Elixir design

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

### Coverage

Source state: HEAD `85023dd` with local changes. Primary review and a second
read-only reviewer checked the complete boundary.

| Responsibility | Traces | Result |
| --- | --- | --- |
| Entry | Creation, normalization, local-value rejection, encode/decode and identity | Source, tests and unchecked-struct probe checked. |
| Thread | Append order, sequences, revisions, stats, reads, portable boundary | Source, tests and ignored-stats probe checked. |
| Composition | Session append/validation and AI projection | Current success/error callers checked. No process ownership here. |

### Evidence, checks, and proof gaps

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

### Sources

- [Thread source](../../lib/jido/thread.ex)
- [Entry source](../../lib/jido/thread/entry.ex)
- [Thread tests](../../test/jido/thread_test.exs)
- [Conversation codec tests](../../test/jido/ai/conversation/conversation_codec_contract_test.exs)
- [AI Projection](../../lib/jido/ai/thread/projection.ex)
- [Conversation obligations](../../test/contracts/jido_ai/conversation.obligations.md)
- [Reach layers](../../.reach.exs)
