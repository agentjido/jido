---
title: Jido.Session component
status: current
last-reviewed: 2026-11-19
---

# Jido.Session component

This record describes the portable Session contract and its design review.

## Release review — 2026-11-19

Reviewed `release/v3` at
[`6fdc009a1edd6261f3e26509fa2905bb9192faa5`](https://github.com/agentjido/jido/commit/6fdc009a1edd6261f3e26509fa2905bb9192faa5)
for [the V3 review queue](https://github.com/agentjido/jido/issues/453).
The review used GPT-6.2 Sol with `xhigh` reasoning.

### Implemented changes

- Agent state uses the portable value checks. Request start checks both
  ownership paths and reports a closed Session before appending a message.
  [#487](https://github.com/agentjido/jido/issues/487)
- Version 1 accepts both field key forms, unambiguous mixed keys, and
  duplicate keys with exactly equal values. It rejects conflicting values
  and struct markers. Missing or nil revision and metadata still use their
  defaults. Malformed nested Thread lists return `:invalid_session`.
  The rollover example handles unsupported versions.
  [#491](https://github.com/agentjido/jido/issues/491)
- AI request start checks Session documents with the Runic canonical
  codec before it returns the Turn. A Session can be valid in BEAM storage
  and return `:invalid_session_identity` at this boundary. The version 1
  document and existing Runic identity projection keep the same format.
  [#494](https://github.com/agentjido/jido/issues/494)
- Session reuses validation after Thread append, map decode, and encode.
  Metadata replacement checks the new metadata once. Constructors share
  value construction and generate a Session ID only when needed.
  [#495](https://github.com/agentjido/jido/issues/495) ·
  [#496](https://github.com/agentjido/jido/issues/496)

Six regression tests failed on the release base. After the changes, all
113 focused tests passed with Elixir 1.18.4 and OTP 27. The call trace
with 256 existing entries confirmed one Thread validation per append,
map decode, and encode. The explicit ID and Thread path made zero UUID
calls.

The review evidence below describes the pinned release before these changes.

| Required check | Evidence |
| --- | --- |
| Public surface | Checked both constructors, shape schemas, lifecycle, validation, the version 1 document, and the Runic identity protocol. |
| API contract usage | Traced Agent state, caller-owned requests, AI Turn Actions, persistence, and the non-AI and rollover examples. |
| Code quality | Counted repeated validation calls and unused UUID generation. Checked constructor and schema duplication. |
| Elixir and OTP design | Checked value ownership, dependencies, Thread composition, and the handoff to the Agent runtime. |

### Public surface and compatibility

- `new/0,1` creates an open Session. It accepts `id`, `now`, `thread`, and
  `metadata`. The default ID is `session_<uuid7>`. The default Thread ID is
  `<session-id>:thread`. A supplied Thread keeps its own identity, entries,
  revision, and times. The Session uses `now` for both of its times.
- `from_thread/1,2` wraps a Thread. It accepts `id`, `created_at`, `updated_at`,
  and `metadata`. Its defaults are `session:<thread-id>` and the Thread's
  times. Both constructors start at the Thread revision and check the result.
- `append/2` accepts an entry, a list of entries, `nil`, or `[]`. An open
  Session returns unchanged for empty input. Each new entry adds one to
  the Session revision. Append keeps the later Session or Thread time. A
  closed Session raises `ArgumentError` on append, including empty input.
- `put_metadata/2` replaces the complete metadata map. This operation and
  the first `close/1` add one to the revision and retain a nondecreasing
  timestamp. Metadata changes remain valid after close. Repeated close
  returns the same value. `open?/1` checks the status.
- `schema/0` and `state_schema/0` return the same closed Joi struct schema.
  The hidden `validate/1` also checks version, revision, time order, Thread
  invariants, and portable metadata. The stored-state schema and full value
  checks differ on the pinned commit. See issue #487 below.
- `encode/1` checks the Session and returns the `jido.session` document with
  `version: 1` under string keys. The document includes the complete Thread.
  `decode/1` accepts the Session struct or a document. It returns a result
  tuple. Its documented error cases are invalid data and unsupported versions.
  `decode!/1` raises `ArgumentError` for a decoder error.
- Version 1 reads atom and string field keys and both status forms. It defaults
  absent and nil `rev` and `metadata` to `0` and `%{}`. The Session revision
  must still be at least the Thread revision. The storage policy permits BEAM
  terms such as tuples and structs. JSON round trips require JSON-compatible
  payloads, refs, and metadata. A Thread atom kind must exist on the reading
  node. String kinds work across nodes without that dependency.
- Runic projects the same document returned by `encode/1`. The Session ID
  names the Session across revisions. The Runic content identity also
  reflects the revision, status, Thread, times, and metadata.

[Session source](../../lib/jido/session.ex) ·
[Session guide](../../guides/data/sessions-and-threads.md)

### Callers and ownership

AI declares the nullable Session schema in Agent state through
`Projection.schema/0`. `StartRequest` chooses a trusted caller's
`:jido_ai_session` first. It otherwise uses the Agent Session or creates
one. It appends the user message and encodes the complete Session in Turn
data. `ProjectConversation`, `CallModel`, `RecordModelAttempt`, the tool
review and result Actions, and `FinalizeTurn` read that data. `FinalizeTurn`
stores the final Session for an Agent-owned request. For a caller-owned
request it returns an entry delta and keeps the Agent state.
[Request start](../../lib/jido/ai/reasoning/actions/start_request.ex) ·
[AI state schema](../../lib/jido/ai/agent.ex) ·
[Turn finalization](../../lib/jido/ai/reasoning/actions/finalize_turn.ex)

The snapshot test covers a legacy module rename with Session history.
The application-owned example uses Session without AI. The rollover example
retains a closed original and creates a new Session. The public
`from_thread/2` and `put_metadata/2` have direct tests. The review found no
production call for either function under `lib/`. Keep both APIs.
[Snapshot tests](../../test/jido/persistence/snapshot_test.exs) ·
[Non-AI example](../../examples/19_sessions_and_conversations/19_08_non_ai_session/README.md) ·
[Rollover example](../../examples/20_context_and_memory_flows/20_04_session_rollover/README.md)

### Defects

| Issue | Impact | Acceptance evidence |
| --- | --- | --- |
| [#487](https://github.com/agentjido/jido/issues/487) P2 | Agent state accepts values that Session rejects. Request start reports a general context error for a closed Agent-owned Session. | Check invalid versions, revisions, times, metadata and Thread state at Agent admission and transition. Preserve valid closed records and return the same request-start lifecycle error for both owners. |
| [#491](https://github.com/agentjido/jido/issues/491) P2 | Decode can select a conflicting ID, replace invalid defaults, or raise on a malformed nested Thread. Rollover raises on an unsupported version. | Keep valid version 1 forms and supported defaults. Return a tagged error for malformed input. Preserve version errors through decode and handle them in rollover. |
| [#494](https://github.com/agentjido/jido/issues/494) P2 | A portable Session that contains a `Date` survives storage, then fails in Runic identity projection or fact creation. | Define the Runic boundary for nested Session and Thread data. Preserve existing storage round trips and supported identity. Test success or early input rejection at the caller. |

The probes used the real AI Agent state schema and request-start Action.
They checked the same closed Session with both owners. They passed an
improper list in the nested Thread to each decoder form. They also checked
a version 2 rollover and ran the encoded Session through Runic identity
and Turn fact creation. The normal identity projection matched the digest
of the version 1 document. A timestamp 60 seconds ahead of the Thread
stayed unchanged after append. This confirms the earlier F3 fix.

### Behavior-preserving cleanups

| Issue | Benefit and evidence | Behavior to preserve |
| --- | --- | --- |
| [#495](https://github.com/agentjido/jido/issues/495) P3 | Reuse checked Thread results and remove the second metadata pass. With 256 existing entries, append, map decode, and encode each called `Thread.validate/1` twice. They called `Entry.validate/1` 515, 768, and 768 times, respectively. | Keep complete boundary validation, results, exceptions, revisions, timestamps, lifecycle, version 1 output, and Runic identity. Repeat the call trace and show fewer passes. |
| [#496](https://github.com/agentjido/jido/issues/496) P3 | Share Session construction and make the ID default lazy. A trace with an explicit ID and an existing Thread counted one unused UUID generation. | Keep both entry points, their distinct ID and time defaults, overrides, the supplied Thread, and existing validation. Verify exact values and zero UUID calls in the traced case. |

### Elixir and OTP boundary

Keep Session and Thread as separate immutable values in Reach
`value_model`. Session owns lifecycle, the outer identity, and the outer
revision. Thread owns entries, sequence assignment, and Thread invariants.
An Agent or caller owns the Session value. AgentServer owns serialized
Turns, and Persistence owns storage and recovery. AI owns projection and
request policy. The Session value needs no process. The review kept the
existing Covenant grouping under `jido_ai.conversation`; obligation I1
covers portable values. The separate Thread review owns its internal
design. [Reach layers](../../.reach.exs) ·
[Conversation obligation](../../test/contracts/jido_ai/conversation.obligations.md) ·
[Thread review](thread.md)

### Verification

- 92 focused tests passed. They covered Session, Thread, conversation, AI
  Turn and model calls, AI Agent state, and snapshots.
- 13 tagged Session and rollover example tests passed.
- 46 ReAct contract and runtime tests passed. The format check and local
  review probes passed.

## Earlier review — 2026-11-10

R5 completed the four checks at an earlier source state. The findings and
verification below record that review.

### Local defect fixes — 2026-11-10

F3 is fixed locally: append retains the later Session or Thread time.
The user requested these fixes without tests. No tests were added or run.
The review findings below describe the source before these fixes. Other
recommendations remain open.

### Public contract at R5

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

### Ownership, dependencies, and callers at R5

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

### Duplication and Elixir design at R5

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

### Coverage at R5

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

### Evidence, checks, and proof gaps at R5

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
