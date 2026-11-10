---
title: Jido.Session component
status: current
last-reviewed: 2026-11-10
---

# Jido.Session component

Purpose: Record the portable Session contract and its design review.
Review result: All four review checks are complete (R5). Findings remain open.
Only the defect fix noted below is authorized for implementation.

## Local defect fixes — 2026-11-10

F3 is fixed locally: append retains the later Session or Thread time.
The user requested these fixes without tests. No tests were added or run.
The review findings below describe the source before these fixes. Other
recommendations remain open.

## Public contract

| Surface | Operations and results |
| --- | --- |
| Schema | `schema/0`, `state_schema/0` return the same strict Joi struct schema. |
| Construction | `new/0,1` creates an open Session. Options are `id`, `now`, `thread`, and `metadata`. `from_thread/1,2` wraps a Thread; options are `id`, `created_at`, `updated_at`, and `metadata`. Invalid values raise `ArgumentError`. |
| Change | `append/2`, `put_metadata/2`, `close/1` return a complete new value. `open?/1` checks status. |
| Portable form | `encode/1` returns a map with type `jido.session` and version 1. `decode/1` accepts a struct or map and returns `{:ok, session}`, `{:error, :invalid_session}`, or `{:error, :unsupported_version}`. `decode!/1` raises `ArgumentError`. |
| Internal export | `validate/1` checks the full value and returns a result tuple. The Runic identity protocol uses `encode/1`. |

The Session owns one Thread, identity, revision, lifecycle, timestamps, and
portable metadata. Its revision is at least the Thread revision. Append adds
the number of new Thread entries to the Session revision. Metadata replacement
and first close each add one. Repeated close is unchanged. Closed Sessions
reject append, including empty append. Metadata can still change after close.
Metadata and close retain nondecreasing timestamps. Append has a time defect
when the Session timestamp is ahead of its Thread (F3).

The map uses `version`, not the root Codec document field `vsn`. Metadata uses
`Jido.Codec.Term`; this is portable BEAM data, not a promise of JSON data.
Decode accepts atom or string field keys. Constructors accept keyword options
and silently ignore unknown option names.

## Ownership, dependencies, and callers

Session is a pure value in Reach `value_model`. It uses Thread, Joi, Id, Term,
and the Runic identity protocol. It owns no GenServer, storage, model message
format, commit, or recovery policy. AI owns model projection.

Current callers include `AI.Thread.Projection.schema/0` and `append/4`,
`AI.Reasoning.Actions.StartRequest` (decode and open check), CallModel,
RecordModelAttempt, FinalizeTurn, and the ReAct review/tool-result Actions.
They pass versioned maps through Turn data and reconstruct the Session.
The Session example uses `close/1`. `from_thread/2` and `put_metadata/2` have
direct contract tests but no production caller found in `lib/`.
`state_schema/0` is used by AI and is not dead code.

## Duplication and Elixir design

- Retain immutable values and explicit owner-driven changes. A process or a
  storage abstraction here would duplicate AgentServer and Persistence.
- **F1 — Design decision, P3, high confidence:** `state_schema/0` is an alias of `schema/0` with no
  distinct rule. Keep it until its public naming decision is made. Do not
  claim that its implementation adds stricter checks.
- **F2 — Design decision, P3, high confidence:** `field/2` silently selects atom keys over string
  keys when both exist. `known_keys?/1` also permits `__struct__`. Define a
  collision and marker policy before changing decode. Session and Thread
  repeat field lookup, version, key, and portable metadata checks. A small
  shared helper can reduce repetition only after those policies agree.
- Session validation checks the Thread again after Joi checks its schema.
  Retain domain invariants, but measure repeat traversal before changing it.
  This matters when AI appends many entries.
- The Session/Thread component split remains Mike's open decision. Current
  one-way dependency supports separate values; the shared Covenant owner does
  not settle the product boundary.

## Coverage

Source state: HEAD `85023dd`, including local changes. Primary review and a
second read-only reviewer covered these rows. No source fix was made.

| Responsibility | Traces | Result |
| --- | --- | --- |
| Value construction and lifecycle | New/from-thread, append, metadata, open/closed, timestamps and revisions | Source and tests checked; F3 reproduced. |
| Portable boundary | Encode/decode, version, keys, metadata and identity protocol | Source, callers, tests and mixed-key probe checked. |
| Composition | Thread validation and AI projection/request callers | Success and invalid input paths checked. |

**F3 — Defect, P2, high confidence.** `lib/jido/session.ex:96` copies the
Thread timestamp into the Session. `from_thread/2` can create a valid Session
with a later `updated_at`. A temporary probe used `updated_at: now + 60_000`,
then appended an entry. The Session time decreased. If `created_at` is also
later, append can reject the next value as invalid. Use
`max(session.updated_at, thread.updated_at)` at append. This changes time
output only when the two times already differ. Verify both cases and ordinary
append before a fix is accepted.

## Evidence, checks, and proof gaps

Reviewed all 229 source lines, all exports, callers in `lib/`, the Session unit
tests, and the conversation codec contract tests. The first focused command
in R5 passed 184 tests. It includes `test/jido/session_test.exs`. The 14 additional
conversation tests passed. Final limits are recorded in the checklist R5 entry.

`jido_ai.conversation.I1` currently owns the portable values. It proves revision,
round-trip, lifecycle, invalid version, unknown field, and unsafe metadata
behavior. It mixes AI projection ownership with feature-neutral values.
Separate proof ownership is still needed. The current tests do not settle
conflicting key forms or whether close must prohibit metadata changes.
No live AI request is needed to test these value contracts.

## Sources

- [Session source](../../lib/jido/session.ex)
- [Thread review](thread.md)
- [Projection caller](../../lib/jido/ai/thread/projection.ex)
- [Request caller](../../lib/jido/ai/reasoning/actions/start_request.ex)
- [Session tests](../../test/jido/session_test.exs)
- [Conversation codec tests](../../test/jido/ai/conversation/conversation_codec_contract_test.exs)
- [Conversation obligations](../../test/contracts/jido_ai/conversation.obligations.md)
- [Reach layers](../../.reach.exs)
