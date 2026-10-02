# Gap analysis: current Jido core, design documents, and V2

Review date: 2026-10-01. Repository: `jido`. Branch: `release/v3`.
V3 source reviewed: `35c9644addfcf20c89f5d2bcaa3c2af045b45859`.
V2 source baseline: tag `v2.3.3`, commit `69f3b40506ce3ea1a2c80b255b737d6c3a453cf2`.
V2 merge behavior also checked at tag `v2.0.0`, commit `5942ae9b2a9fd9f00cc715a83b7253d4d40d8e54`.

This is the single consolidated gap analysis requested by the user. It covers all 16 numbered topics, VISION, the index, the seam template/instructions, and the four delivery records. The comparison is against current `lib/`; test code and package configuration supply supporting evidence. It does not review sibling packages or implement changes.

The current code is canonical for present behavior. When intent is unclear, use the V2 API as the reference. Explicit V3 decisions take precedence. Builder removal is explicit. Deep merge for `set/2` is selected under the V2 rule; the source still implements shallow merge. Immediate validation, V3 write ownership, and validation-only state schemas are now explicit user decisions. Strict durable portability is now selected for saved values after conversion.

Review status: **Pending approval**. The user has not approved this report or any complete topic document. Source, historical behavior, recommendations, and user decisions are stated separately.

## How to work through this file

Use the stable `GAP-001` through `GAP-069` numbers in discussion. Each entry states the design claim, current implementation, V2 approach, reconciliation question/action, and source evidence. A document correction normally follows current code. An API or migration decision needs a stated intent before a code change. External or paused service work remains outside the active core queue.

Several entries are related. Resolve the owner contract once, then update every listed dependent topic. The IDs identify review questions, not 69 independent implementation defects.

V2 research uses primary source from the pinned local Git tag. Links point to that immutable commit on GitHub. No V2 checkout, dependency substitution, source edit, network service run, or publication was needed. Where V2 has no equivalent, the report says so; an older V3 proposal is not called a V2 API.

## Decision index

| Gap | Topic | Type | Question or correction | State |
| --- | --- | --- | --- | --- |
| [GAP-001](#gap-001) | 00 Overview | Document correction | Remove Builder from supported authoring | Settled: user intentionally removed Builder |
| [GAP-002](#gap-002) | 00 Overview | Document correction | Separate live state from portable stored data | Live direction set by the V2 rule; durable policy settled in GAP-008 |
| [GAP-003](#gap-003) | 00 Overview | Document correction | Resolve the preparation and selection order conflict | Open |
| [GAP-004](#gap-004) | 00 Overview | Evidence update | Remove completed work from open Overview gaps | Open |
| [GAP-005](#gap-005) | 01 Agent | Code change selected | Restore V2 deep merge for set/2 | Selected by the V2 fallback rule; not implemented |
| [GAP-006](#gap-006) | 01 Agent | Resolved API decision | Retain immediate validation and V3 write ownership | Settled: user selected both V3 rules |
| [GAP-007](#gap-007) | 01 Agent | Resolved API decision | Retain validation-only state schemas and checked creation defaults | Settled: user selected the V3 schema policy |
| [GAP-008](#gap-008) | 01 Agent | Resolved API decision | Reject nonportable saved values after persistence conversion | Settled: user selected V3 durable rejection |
| [GAP-009](#gap-009) | 02 Agent authoring | Resolved API decision | Keep V3 block configuration for module schemas, metadata, Plugins, and routes | Settled: user selected V3 blocks |
| [GAP-010](#gap-010) | 02 Agent authoring | Resolved API decision | Keep named routes generating map-input Signal helpers | Settled: user explicitly selected the current helper API |
| [GAP-011](#gap-011) | 02 Agent authoring | Document correction | Correct inline Action lookup to route_action!/1 | Corrected in authoring design |
| [GAP-012](#gap-012) | 02 Agent authoring | Resolved API decision | Require plain maps for both route-default forms | Settled: user rejected the legacy struct exception |
| [GAP-013](#gap-013) | 02 Agent authoring | Document correction | Remove obsolete compiler interface metadata | Corrected in authoring design |
| [GAP-014](#gap-014) | 02 Agent authoring | Evidence update | Correct Codec and Registry evidence paths | Paths corrected; remaining Builder cleanup in GAP-001 |
| [GAP-015](#gap-015) | 03 Agent identity | Document correction | State exact Ref conversion result shapes | Corrected in identity documents |
| [GAP-016](#gap-016) | 03 Agent identity | Resolved migration decision | Keep flexible local partitions and stable string durable partitions | Settled: user selected the distinction |
| [GAP-017](#gap-017) | 04 Turn evaluation | Evidence update | Refresh evaluator alignment without recreating old work | Open |
| [GAP-018](#gap-018) | 05 Plugins | Resolved API decision | Keep one Plugin module with callback-derived capabilities | Settled: user intentionally simplified to one module |
| [GAP-019](#gap-019) | 05 Plugins | Document correction | Document Plugin version, owner option filtering, and validation | Corrected in Plugin design |
| [GAP-020](#gap-020) | 05 Plugins | Document correction | Permit reconstructed local values after Plugin load | Corrected under selected live/durable policy |
| [GAP-021](#gap-021) | 05 Plugins | Resolved API decision | Keep the required after_commit/3 failure boundary | Settled: user selected the current V3 hook contract |
| [GAP-022](#gap-022) | 05 Plugins | Document correction | Give Scheduler requirements an actual definition and owner | Corrected in Plugin design and delivery ledger |
| [GAP-023](#gap-023) | 05 Plugins | Code change selected | Remove core Scheduler durable delivery | Settled: removal selected; code cleanup pending |
| [GAP-024](#gap-024) | 05 Plugins | Migration decision | Document SensorManager instead of the removed V2 Sensor API | Open |
| [GAP-025](#gap-025) | 05 Plugins | Document correction | Add a concise inventory of built-in capability contracts | Open |
| [GAP-026](#gap-026) | 06 Commit and effects | Document correction | Correct settlement when a Turn has no Directives | Corrected in commit design and alignment |
| [GAP-027](#gap-027) | 06 Commit and effects | Document correction | Limit nondurable checkpoint requirements to named instances | Open |
| [GAP-028](#gap-028) | 06 Commit and effects | API decision | Resolve recoverable work with opaque custom checkpoints | Open |
| [GAP-029](#gap-029) | 07 Persistence | Migration decision | Replace format-1/2 read promises with format-3-only behavior | Open |
| [GAP-030](#gap-030) | 07 Persistence | Migration decision | Confirm stable namespace as a durable Agent prerequisite | Open |
| [GAP-031](#gap-031) | 07 Persistence | Migration decision | Remove unsupported dual-key reads and collision gates | Open |
| [GAP-032](#gap-032) | 07 Persistence | Document correction | Document opaque conditional-write tokens | Open |
| [GAP-033](#gap-033) | 07 Persistence | Document correction | Assign the shared Store API a public contract | Open |
| [GAP-034](#gap-034) | 07 Persistence | Document correction | Update the adapter inventory and backend limits | Open |
| [GAP-035](#gap-035) | 07 Persistence | API decision | Retain or approve migration of raw storage failures | Open |
| [GAP-036](#gap-036) | 07 Persistence | Evidence update | Keep Bedrock service proof separate from adapter implementation | Open |
| [GAP-037](#gap-037) | 08 Agent Server | Evidence update | Update completed initial-durability follow-up claims | Open |
| [GAP-038](#gap-038) | 08 Agent Server | Document correction | Add after_commit to Outcome stages | Corrected in Server design and alignment |
| [GAP-039](#gap-039) | 08 Agent Server | Document correction | Document hook timeout, directing phase, and reentry | Corrected in Server design and alignment |
| [GAP-040](#gap-040) | 08 Agent Server | Document correction | Clarify copied local handles in runtime checkpoints | Open |
| [GAP-041](#gap-041) | 08 Agent Server | Document correction | Remove the unavailable module-key upgrade mode | Open |
| [GAP-042](#gap-042) | 08 Agent Server | Document correction | Describe upgrade and cancellation raw controls | Open |
| [GAP-043](#gap-043) | 09 Jido instance | Document correction | Correct unnamed local and namespaced durable behavior | Open |
| [GAP-044](#gap-044) | 10 Runtime topology | Document correction | Update worker inventory and Plugin owner terminology | Open |
| [GAP-045](#gap-045) | 11 Topology control plane | Document correction | Define accepted-target storage and restore | Open |
| [GAP-046](#gap-046) | 11 Topology control plane | Document correction | Define pending move and failed target-write recovery | Open |
| [GAP-047](#gap-047) | 11 Topology control plane | Evidence update | Refresh ownership cleanup and settlement evidence | Open |
| [GAP-048](#gap-048) | 11 Topology control plane | Evidence update | Bring Topology acceptance coverage through requirement 101 | Open |
| [GAP-049](#gap-049) | 11 Topology control plane | Scope correction | Keep distributed reference contracts out of the core backlog | Outside core; no implementation requested |
| [GAP-050](#gap-050) | 12 Errors and contracts | Confirmed code gap | Register the three emitted cancellation and upgrade codes | Open |
| [GAP-051](#gap-051) | 12 Errors and contracts | API decision | Resolve the universal code rule for ordinary validation errors | Open |
| [GAP-052](#gap-052) | 12 Errors and contracts | Document correction | Update public shaped values and internal-type inventories | Open |
| [GAP-053](#gap-053) | 12 Errors and contracts | Document correction | Expand the protocol-control registry to actual results | Open |
| [GAP-054](#gap-054) | 13 Observability | Document correction | Make the event-family inventories agree | Open |
| [GAP-055](#gap-055) | 13 Observability | Document correction | Add after_commit to the semantic stage vocabulary | Open |
| [GAP-056](#gap-056) | 13 Observability | Document correction | Add Plugin owner module fields to the allowlist table | Open |
| [GAP-057](#gap-057) | 13 Observability | Document correction | Add shared Store events and consumer policy | Open |
| [GAP-058](#gap-058) | 13 Observability | Migration decision | Correct legacy Observe and OpenTelemetry compatibility claims | Open |
| [GAP-059](#gap-059) | 90 Package boundaries | Document correction | Classify Store and local Topology target ownership | Open |
| [GAP-060](#gap-060) | 90 Package boundaries | Migration decision | Make the V2-to-V3 public migration inventory explicit | Open |
| [GAP-061](#gap-061) | 99 Delivery | Evidence update | Separate published beta.1 evidence from the current candidate | Open |
| [GAP-062](#gap-062) | 99 Delivery | Release decision | Record Git dependency pins and the Hex publication gate | Open |
| [GAP-063](#gap-063) | 99 Delivery | Evidence update | Replace the obsolete floor failure with exact-commit evidence | Open |
| [GAP-064](#gap-064) | 99 Delivery | Document correction | Align release commands with current test categories | Open |
| [GAP-065](#gap-065) | 99 Delivery | Document correction | Replace closed ranges with the current requirement inventory | Open |
| [GAP-066](#gap-066) | 99 Delivery | Release decision | Keep beta-only exceptions from approving another release | Open |
| [GAP-067](#gap-067) | Cross-topic documents | Document correction | Separate approval status from implementation status | Open |
| [GAP-068](#gap-068) | Cross-topic documents | Evidence update | Replace missing paths and obsolete line evidence | Open |
| [GAP-069](#gap-069) | Cross-topic documents | Document correction | Apply the review authority and completion rules consistently | Open |

## 00 Overview

<a id="gap-001"></a>

### GAP-001: Remove Builder from supported authoring

**Type:** Document correction. **State:** Settled: user intentionally removed Builder.

**Design:** VISION, OVR-REQ-008/063, AGT-REQ-008/023/029, AUTH-REQ-001/035–039/053/054/061, TOP-REQ-059, and the package inventory retain Builder.

**Current V3:** Agent and Topology Builder modules are absent. Module blocks, direct data, and Codec remain.

**V2 approach:** V2.3.3 had module keyword authoring and Agent constructors. Its library has no Jido.Agent.Builder or Jido.Topology.Builder. Builder retention describes an earlier V3 API, not a V2 requirement.

**Reconciliation:** Remove Builder requirements, examples, parity rows, and source/test claims. Retire Builder-only requirement IDs. Keep Codec. This is an explicit user decision.

**Evidence:** [docs/design/00_overview/design.md:114](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/00_overview/design.md:114); [docs/design/02_agent-authoring/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/02_agent-authoring/design.md); [lib/jido/agent.ex:108](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent.ex:108); [lib/jido/topology.ex:5](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/topology.ex:5); [lib/jido/agent.ex:71](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent.ex#L71).

<a id="gap-002"></a>

### GAP-002: Separate live state from portable stored data

**Type:** Document correction. **State:** Live direction set by the V2 rule; durable policy settled in GAP-008.

**Design:** OVR-REQ-007, AGT-REQ-005/036–038, PLG-REQ-017/049, SRV-REQ-003, RT-REQ-027, and ERR-REQ-022 use portable-state or no-handle language too broadly.

**Current V3:** Live state accepts local values when the declared schema permits them. Durable checkpoints reject prohibited values after conversion. Server-owned task and monitor fields remain private.

**V2 approach:** V2 set/2 did not validate state, and validate/2 applied schema rules without a general portability gate. The Server also injected reserved runtime-related fields into Agent state. This does not justify exposing V3 Server private fields.

**Reconciliation:** Correct the live-state ban. Permit schema-approved local values. Keep Server private fields private. Keep the durable restriction selected in GAP-008; do not restore V2 runtime injection. The Agent owner wording is corrected; cross-topic corrections remain.

**Evidence:** [docs/design/01_agent/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/01_agent/design.md); [lib/jido/agent.ex:121](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent.ex:121); [lib/jido/agent/state.ex:48](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/state.ex:48); [test/jido/agent/portable_state_test.exs:24](/Users/mhostetler/Source/Jido/proj_jido_core/jido/test/jido/agent/portable_state_test.exs:24); [lib/jido/agent/state.ex:37](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent/state.ex#L37); [lib/jido/agent_server/state.ex:256](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server/state.ex#L256).

<a id="gap-003"></a>

### GAP-003: Resolve the preparation and selection order conflict

**Type:** Document correction. **State:** Open.

**Design:** Overview alignment GAP-001 says route selection occurs before Plugin preparation. OVR-REQ-014 and topic 04 require preparation first.

**Current V3:** Direct evaluation prepares Plugin inputs, then selects from the source Signal. Live admission prepares inputs before Runner selection. Plugins cannot replace source selection.

**V2 approach:** V2 Server ran handle_signal and prepare_signal before routing, then prepare_action after routing. Those older callbacks could override routing or transform a Signal. V2 therefore supports the timing reference, not the V3 immutability rule.

**Reconciliation:** State the implemented order once: pure preparation, live admission where applicable, selection, execution, reduction, validation. Remove the conflicting Overview gap text.

**Evidence:** [docs/design/00_overview/alignment.md:268](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/00_overview/alignment.md:268); [docs/design/04_turn-evaluation/design.md:48](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/04_turn-evaluation/design.md:48); [lib/jido/agent/runner.ex:104](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/runner.ex:104); [lib/jido/agent_server.ex:37](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server.ex#L37).

<a id="gap-004"></a>

### GAP-004: Remove completed work from open Overview gaps

**Type:** Evidence update. **State:** Open.

**Design:** The Overview briefing still lists unsafe durable lifecycle and deferred live topology control, while its alignment marks initial records, tombstones, and additive updates complete.

**Current V3:** Revision-zero durable creation, ready-only publication, write-authority loss, tombstones, additive updates, and exact-node placement exist.

**V2 approach:** V2 persisted snapshots on lifecycle operations and used Pod reconciliation/mutation. It had no V3 CAS lifecycle or ready-only revision-zero record gate.

**Reconciliation:** Replace the old open-work rows with current limits and current owner evidence. Retain distributed authority as outside core. Do not implement work already present.

**Evidence:** [docs/design/00_overview/README.md:51](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/00_overview/README.md:51); [lib/jido/agent_server/server_lifecycle.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/server_lifecycle.ex:1); [lib/jido/persistence/record.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/record.ex:1); [lib/jido/topology/controller.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/topology/controller.ex:1); [lib/jido/persist.ex:167](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/persist.ex#L167).


## 01 Agent

<a id="gap-005"></a>

### GAP-005: Restore V2 deep merge for set/2

**Type:** Code change selected. **State:** Selected by the V2 fallback rule; not implemented.

**Design:** AGT-REQ-015 and the Agent alignment require deep merge.

**Current V3:** set/2 calls Map.merge/2. A supplied nested map replaces the old map. Tests explicitly require that shallow behavior.

**V2 approach:** V2 Agent.set/2 and generated module set/2 called Agent.State.merge/2. Plain maps and keyword lists merged recursively. Ordinary lists and structs were replaced. An empty right keyword list retained the left keyword list.

**Reconciliation:** Use V2 deep merge behavior under the user fallback rule. Update code, function documentation, shallow replacement tests, and migration text together in a later implementation task. Add no flag or clear method for this decision.

**Evidence:** [docs/design/01_agent/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/01_agent/design.md); [lib/jido/agent.ex:370](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent.ex:370); [test/jido/agent_test.exs:556](/Users/mhostetler/Source/Jido/proj_jido_core/jido/test/jido/agent_test.exs:556); [test/jido/agent/replacement_test.exs:25](/Users/mhostetler/Source/Jido/proj_jido_core/jido/test/jido/agent/replacement_test.exs:25); [lib/jido/agent.ex:1475](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent.ex#L1475); [lib/jido/util/deep_merge.ex:19](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/util/deep_merge.ex#L19).

<a id="gap-006"></a>

### GAP-006: Decide whether set/2 continues to validate

**Type:** Resolved API decision. **State:** Settled: user selected V3 immediate validation and write ownership on 2026-10-01.

**Design:** AGT-REQ-015 requires a new validated Agent. The current public contract rejects Plugin-owned attributes.

**Current V3:** set/2 validates domain keys and the complete next state. It returns an error for invalid state and leaves the source Agent unchanged.

**V2 approach:** V2 set/2 merged without validation. The caller invoked validate/2 separately. It did not apply the V3 domain/Plugin write boundary.

**Decision:** Retain immediate validation of the complete combined state before set/2 returns a successful result. Do not require a separate caller validation step. Related domain changes can be supplied in one call. Retain V3 write ownership: domain updates cannot change Plugin-owned fields, and each Plugin can replace only its own field. These are explicit V3 decisions and take precedence over the V2 fallback rule.

**Reconciliation:** The current code already implements the selected behavior. The validation timing and write ownership questions are closed. The Agent design and alignment now record the decisions under AGT-REQ-012/013/015. GAP-005 still requires the separate deep merge change. Schema policy in GAP-007 is also settled; durable portability in GAP-008 is settled. These decisions do not approve the complete Agent documents.

**Evidence:** [docs/design/01_agent/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/01_agent/design.md); [lib/jido/agent.ex:364](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent.ex:364); [lib/jido/agent.ex:414](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent.ex:414); [lib/jido/agent.ex:1475](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent.ex#L1475).

<a id="gap-007"></a>

### GAP-007: Document validation-only schemas and initialization defaults

**Type:** Resolved API decision. **State:** Settled: user selected the V3 schema policy on 2026-10-01.

**Design:** AGT-REQ-007 describes initial defaults, but the design does not fully state the current schema restrictions or the difference between input parsing and stored-value validation.

**Current V3:** State schemas reject transforms, coercion, Codec, Lazy, and StringBoolean conversion. Initialization parses defaults once; later checks validate stored values. Initial state is deep-merged over defaults.

**V2 approach:** V2 accepted NimbleOptions and Zoi schemas and called Jido.Action.Schema.validate. It built initial defaults separately. It had no current V3 recursive validation-only schema policy.

**Decision:** Convert input before it becomes Agent state. Apply and check defaults during creation. Later state validation checks stored values without substituting defaults or changing values. State schemas contain defaults and validation rules; conversion effects are rejected. This explicit V3 decision takes precedence over the V2 fallback rule.

**Reconciliation:** The policy question is closed. The Agent design and alignment record the contract in AGT-REQ-007/046/047. Current core code already implements the policy. Topics 04, 05, and 12 still need their schema descriptions checked against this owner contract. The Zoi upstream and released-dependency gate remain open under GAP-062.

**Zoi dependency:** The voice review identified the outstanding Zoi work as relevant. The [Jido integration issue](https://github.com/agentjido/jido/issues/389) and [upstream object-intersection fix](https://github.com/phcurado/zoi/pull/203) are still open as checked on 2026-10-01. Current Jido pins a fork with checked defaults, stored-value validation, and the intersection fix. Existing tests cover creation, stored-state validation, restore, Plugin output, and generated intersection cases. These tests were inspected, not rerun in this voice turn. A compatible released dependency remains a release question under GAP-062. The selected schema policy is settled; the upstream defect and dependency gate do not reopen that decision.

**Evidence:** [docs/design/01_agent/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/01_agent/design.md); [lib/jido/agent/state.ex:20](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/state.ex:20); [lib/jido/agent/state.ex:106](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/state.ex:106); [lib/jido/agent.ex:111](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent.ex#L111); [lib/jido/agent/state.ex:46](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent/state.ex#L46).

<a id="gap-008"></a>

### GAP-008: Decide the strict durable portability restriction

**Type:** Resolved API decision. **State:** Settled: user selected rejection of nonportable saved values on 2026-10-01.

**Design:** OVR-REQ-043, PERS-REQ-010, and ERR-REQ-024 require portable records. Agent requirements incorrectly extend that rule to all live acceptance.

**Current V3:** Agent checkpoints and persistence records reject PIDs, ports, references, functions, improper lists, and non-byte-aligned bitstrings. Custom conversion can produce a portable stored value.

**V2 approach:** V2 checkpoints had no general recursive portability gate. ETS stored terms; File and Redis serialized Erlang terms. V2 Scheduler separately rejected local handles in durable cron messages. Stored handles did not recreate their resources.

**Decision:** Reject nonportable saved values. Keep the current recursive checkpoint check after save conversion and before restore conversion. Plugins or custom Agent callbacks can save portable data and reconstruct local resources on restore. This is an explicit durable V3 decision. It does not add a blanket live-state ban.

**Reconciliation:** The policy question is closed. Current code already implements this rejection. The Agent design and alignment now separate live schema validation from durable portability under AGT-REQ-036/037/041/048. The obsolete blanket live ban AGT-REQ-005 and unused live portability exclusion AGT-REQ-038 are retired. Other topics still need broad portability wording corrected under GAP-002. Resource reconstruction does not follow from serializing a handle.

**Evidence:** [docs/design/07_persistence/design.md:100](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/07_persistence/design.md:100); [lib/jido/agent/checkpoint.ex:31](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/checkpoint.ex:31); [lib/jido/portable_term.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/portable_term.ex:1); [lib/jido/persist.ex:555](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/persist.ex#L555); [lib/jido/storage/file.ex:84](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/storage/file.ex#L84); [lib/jido/scheduler.ex:280](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/scheduler.ex#L280).


## 02 Agent authoring

<a id="gap-009"></a>

### GAP-009: Replace keyword and block parity with the current module API

**Type:** Resolved API decision. **State:** Settled: user selected the V3 block form on 2026-10-01.

**Design:** AUTH-REQ-009/010 and the supported-form table promise combined keyword and Spark block configuration.

**Current V3:** Standalone use Jido.Agent accepts name, description, vsn, and extensions. Schema, routes, Plugins, and metadata belong in blocks. Combined Topology hosting uses its own configuration path.

**V2 approach:** V2 module authoring used use Jido.Agent keyword configuration, including schema, plugins, and strategy. It had no equivalent current Spark Agent block contract.

**Decision:** Keep the V3 block form for standalone module schema, metadata, Plugins, and routes. Keep only name, description, vsn, and extensions as module options. Direct map/keyword Agent.new/1 construction remains supported. Combined Topology hosting retains its separate configuration path.

**Reconciliation:** The API question is closed. Current code already implements the selected form. The authoring design and alignment record AUTH-REQ-009/063 and retire the obsolete mixed-form duplicate rule AUTH-REQ-010. V2 keyword module examples still need migration to blocks; direct keyword data must not be removed as a side effect.

**Evidence:** [docs/design/02_agent-authoring/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/02_agent-authoring/design.md); [lib/jido/agent/dsl/compiler.ex:66](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/dsl/compiler.ex:66); [test/jido/agent/authoring_test.exs:722](/Users/mhostetler/Source/Jido/proj_jido_core/jido/test/jido/agent/authoring_test.exs:722); [lib/jido/agent.ex:71](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent.ex#L71).

<a id="gap-010"></a>

### GAP-010: Replace define interfaces with as: Signal helpers

**Type:** Resolved API decision. **State:** Settled: user explicitly selected the current route-based helper API on 2026-10-01.

**Design:** AUTH-REQ-021–034 and 059 describe positional arguments, define blocks, bang Signal constructors, and live call helpers.

**Current V3:** route ..., as: :add generates `add_signal(input, envelope_opts)` with an empty option list by default. It returns a tagged Signal result. No positional argument list, generated bang helper, or generated live call helper exists.

**V2 approach:** V2 used Agent.cmd for Action arguments and AgentServer.call/cast for Signals. It had no equivalent define or as: interface generator.

**Decision:** Keep the smaller helper API. A route such as route "counter.add", MyApp.Add, as: :add generates add_signal with plain map input and optional envelope options. The helper builds a Signal only; direct and live execution remain explicit. The user stated that the earlier define keyword was removed by design.

**Reconciliation:** The API question is closed. Current code already implements this form. The authoring design, briefing, and alignment now record it. AUTH-REQ-026/027/029/031/032/059 are retired. Retain envelope protection, omitted-value behavior, fresh ID/time, and command-time validation. AUTH-REQ-064 makes plain-map input rejection explicit. No implementation change is required.

**Evidence:** [docs/design/02_agent-authoring/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/02_agent-authoring/design.md); [lib/jido/agent/dsl/generator.ex:4](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/dsl/generator.ex:4); [lib/jido/agent/interface.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/interface.ex:1); [lib/jido/agent.ex:30](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent.ex#L30); [lib/jido/agent_server.ex:331](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server.ex#L331).

<a id="gap-011"></a>

### GAP-011: Correct inline Action lookup to route_action!/1

**Type:** Document correction. **State:** Corrected in the authoring design on 2026-10-01; complete document approval remains pending.

**Design:** AUTH-REQ-020 and examples name route_action/1.

**Current V3:** Generated modules expose route_action!/1 for inline Action lookup. The documented non-bang lookup does not exist.

**V2 approach:** V2 accepted Action modules and Instruction values, not this inline-route lookup API.

**Reconciliation:** The authoring design now records the current API.  Document route_action!/1, its return and raise behavior, and supported reuse in direct data or Registry entries. Do not invent a tagged variant to match an old document.

**Evidence:** [docs/design/02_agent-authoring/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/02_agent-authoring/design.md); [lib/jido/agent/definition.ex:70](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/definition.ex:70); [lib/jido/agent.ex:30](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent.ex#L30).

<a id="gap-012"></a>

### GAP-012: Resolve the legacy struct route-default exception

**Type:** Resolved API decision. **State:** Settled: user selected plain maps and rejected the legacy struct exception on 2026-10-01.

**Design:** AUTH-REQ-007 permits structs in the legacy {target, defaults} route form; AUTH-REQ-008 restricts explicit defaults to a plain map.

**Current V3:** All defaults, including tuple defaults, must be plain maps. Source Signal data shallowly replaces route-default keys. This merge is separate from Agent.set/2.

**V2 approach:** V2.3.3 used an Action module alone to receive Signal data. A tuple {module, params} supplied fixed Action parameters and ignored Signal data; it was not a fallback-default merge. The Server guard accepted any map, including a struct. The pinned Signal v2.2.2 Router accepted arbitrary target terms. This proves permissive routing, not universal acceptance by every Action schema. V3 fallback defaults and the plain-map restriction are separate compatibility decisions.

**Decision:** Keep plain maps for explicit and tuple route defaults. Remove the legacy struct exception. Current V3 fallback behavior stays in place: supplied Signal fields override defaults. Do not restore V2 fixed-parameter handling.

**Reconciliation:** The API question is closed. Current code already implements the selected rule. AUTH-REQ-007/008 and the owner briefing/alignment now state it. Convert legacy struct defaults explicitly with Map.from_struct where appropriate. The set/2 deep-merge decision does not apply to route input. No implementation change is required.

**Evidence:** [V2 fixed parameter handling](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server.ex#L2034); [V2 Signal target acceptance](https://github.com/agentjido/jido_signal/blob/cb1d04cb6d1e88094c4c0cced2555cf82dc54e6b/lib/jido_signal/router/validator.ex#L126); [docs/design/02_agent-authoring/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/02_agent-authoring/design.md); [lib/jido/agent/authoring.ex:28](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/authoring.ex:28); [lib/jido/agent.ex:43](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent.ex:43); [lib/jido/agent_server/signal_router.ex:26](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server/signal_router.ex#L26).

<a id="gap-013"></a>

### GAP-013: Remove obsolete compiler interface metadata

**Type:** Document correction. **State:** Corrected in the authoring design on 2026-10-01; complete document approval remains pending.

**Design:** AUTH-REQ-012 names __agent_config__/0 and __agent_interfaces__/0. The interface tables describe the earlier generated API.

**Current V3:** __agent_config__/0 remains internal metadata. __agent_interfaces__/0 is absent. Signal functions are generated directly from current routes.

**V2 approach:** V2 generated metadata/accessor functions from module options, but had no current interface metadata API.

**Reconciliation:** The authoring design now records the current API.  Remove the absent metadata function and old interface schemas. Preserve the private status of actual compiler metadata.

**Evidence:** [docs/design/02_agent-authoring/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/02_agent-authoring/design.md); [lib/jido/agent/dsl/compiler.ex:54](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/dsl/compiler.ex:54); [lib/jido/agent/dsl/generator.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/dsl/generator.ex:1); [lib/jido/agent.ex:2](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent.ex#L2).

<a id="gap-014"></a>

### GAP-014: Correct Codec and Registry evidence paths

**Type:** Evidence update. **State:** Shared Codec paths corrected in the authoring alignment on 2026-10-01; remaining Builder parity cleanup is tracked in GAP-001.

**Design:** Authoring evidence names Agent-local codec/data.ex and codec/registry.ex paths.

**Current V3:** Shared implementations are lib/jido/codec/data.ex and lib/jido/codec/registry.ex. Agent, Plugin, and Topology Codecs use the shared encoding boundary.

**V2 approach:** V2.3.3 has no Agent or Topology authoring Codec or trusted Registry equivalent. Its persistence term encoding is not an authoring Codec.

**Reconciliation:** Correct paths and owner references. Keep trusted decode, closed fields, limits, and authoring/checkpoint separation. Remove Builder from extension-lowering parity claims.

**Evidence:** [docs/design/02_agent-authoring/alignment.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/02_agent-authoring/alignment.md); [lib/jido/codec/data.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/codec/data.ex:1); [lib/jido/codec/registry.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/codec/registry.ex:1); [lib/jido/agent/codec.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/codec.ex:1); [lib/jido/persist.ex:388](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/persist.ex#L388).


## 03 Agent identity

<a id="gap-015"></a>

### GAP-015: State exact Ref conversion result shapes

**Type:** Document correction. **State:** Corrected in the identity design and alignment on 2026-10-01; complete document approval remains pending.

**Design:** The identity public table describes conversion maps without consistently stating tagged versus bang results.

**Current V3:** Ref.to_map/1 returns {:ok, map} or {:error, error}; to_map!/1 returns the map or raises. The encoded value is version 1 with closed string keys.

**V2 approach:** V2 has no Jido.Agent.Ref. It used Agent IDs, local Registry keys, and module-dependent persistence keys.

**Reconciliation:** The identity design and alignment now record the current result shapes.  Correct the public table and examples. Keep the V3 Ref contract; there is no V2 conversion API to restore.

**Evidence:** [docs/design/03_agent-identity/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/03_agent-identity/design.md); [lib/jido/agent/ref.ex:96](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/ref.ex:96); [lib/jido/agent/ref.ex:116](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/ref.ex:116); [lib/jido.ex:496](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido.ex#L496).

<a id="gap-016"></a>

### GAP-016: Separate legacy local partitions from durable Ref partitions

**Type:** Resolved migration decision. **State:** Settled: user selected local compatibility and stable durable partitions on 2026-10-01.

**Design:** ID-REQ-026 preserves non-string local partition options while stable Refs require nil or a nonempty string.

**Current V3:** Legacy local APIs accept broader partition values. Durable identity passes through Ref validation, which cannot encode an arbitrary old partition value.

**V2 approach:** V2 Registry partition keys used an arbitrary partition value plus Agent ID. V2 storage keys were {agent_module, agent_id}; they did not establish the V3 partitioned durable identity.

**Decision:** Keep flexible local partitions for legacy ID/PID APIs. A durable Ref uses a nonempty string partition or nil. Applications supply a stable string mapping for legacy values before durable use; core does not silently stringify arbitrary terms.

**Reconciliation:** The partition question is closed. ID-REQ-003/026 and the identity alignment now state the selected distinction. Current code already implements it. No code change is required. This does not approve old storage-key migration promises in GAP-031 or the complete identity documents.

**Evidence:** [docs/design/03_agent-identity/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/03_agent-identity/design.md); [lib/jido/agent/ref.ex:21](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/ref.ex:21); [lib/jido/persistence/identity.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/identity.ex:1); [lib/jido.ex:496](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido.ex#L496); [lib/jido/persist.ex:629](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/persist.ex#L629).


## 04 Turn evaluation

<a id="gap-017"></a>

### GAP-017: Refresh evaluator alignment without recreating old work

**Type:** Evidence update. **State:** Open.

**Design:** Topic 04 names v3-spike and old mixed Plugin cleanup work. Overview also carries the conflicting order in GAP-003.

**Current V3:** Runner and Pipeline implement shared direct/live finalization, prepared/runtime separation, fixed source selection, Directive validation, owned-state protection, and complete candidate validation.

**V2 approach:** V2 direct Agent.cmd evaluated Actions through a Strategy. Signal routing and Plugin Signal hooks lived in AgentServer. It had no shared V3 Signal-to-Turn contract.

**Reconciliation:** Keep the current V3 evaluator. Replace old branch, module, and completed-work evidence. Explain the V2-to-V3 command and routing change in migration text, not as a missing evaluator feature.

**Evidence:** [docs/design/04_turn-evaluation/alignment.md:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/04_turn-evaluation/alignment.md:1); [lib/jido/agent/runner.ex:166](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/runner.ex:166); [lib/jido/agent/plugin/pipeline.ex:17](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/plugin/pipeline.ex:17); [lib/jido/agent_server.ex:49](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server.ex#L49).


## 05 Plugins

<a id="gap-018"></a>

### GAP-018: Replace separate facet authoring with callback-derived owners

**Type:** Resolved API decision. **State:** Settled: user explicitly selected one Plugin module on 2026-10-01.

**Design:** Topic 05 and OVR-GAP-010 describe a callback-free package that selects four separate facet modules. README and alignment disagree about mixed declaration cleanup.

**Current V3:** One use Jido.Plugin module implements optional callbacks. Core derives owner roles. Each manifest owner is nil or the same package module; separate selected modules are rejected.

**V2 approach:** V2 also used one Plugin module, with broader metadata, mount, Signal, Action, child, subscription, and persistence callbacks. Delegation was ordinary Elixir code.

**Decision:** Keep one Plugin module with optional callbacks. The user intentionally returned to this form because separate authoring modules became too complex. Larger Plugins can delegate internally. Keep core ownership and timing rules.

**Reconciliation:** The API question is closed. The Plugin design, briefing, and alignment now record this decision. Current code already implements the form; no code change is required.  Align docs with one callback module and four execution owners. Keep owner modules as core wrappers/context providers, not author behaviours. Record the earlier V3 facet migration. This direction agrees with the V2 single-module shape.

**Evidence:** [docs/design/05_plugins/README.md:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/05_plugins/README.md:1); [lib/jido/plugin.ex:3](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin.ex:3); [lib/jido/plugin/manifest.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin/manifest.ex:1); [lib/jido/plugin.ex:195](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/plugin.ex#L195).

<a id="gap-019"></a>

### GAP-019: Document Plugin version, owner option filtering, and validation

**Type:** Document correction. **State:** Corrected in the Plugin design on 2026-10-01; complete document approval remains pending.

**Design:** Old manifest selection and option tables do not fully describe callback selection or option_keys.

**Current V3:** use Jido.Plugin accepts only vsn and option_keys. Version defaults to 1. Optional option_keys restricts options by owner. validate_options/1 participates in live configuration validation.

**V2 approach:** V2 Plugin metadata included vsn and config_schema. Plugin instances parsed configuration maps; current per-owner keyword filtering had no equivalent.

**Reconciliation:** The Plugin design now records the current contract.  Replace the declaration/configuration table. State version ownership, callback-derived capability checks, per-owner options, and validation timing. Link existing tests.

**Evidence:** [lib/jido/plugin.ex:114](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin.ex:114); [lib/jido/plugin/normalizer.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin/normalizer.ex:1); [lib/jido/plugin/manifest.ex:21](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin/manifest.ex:21); [lib/jido/plugin.ex:67](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/plugin.ex#L67).

<a id="gap-020"></a>

### GAP-020: Permit reconstructed local values after Plugin load

**Type:** Document correction. **State:** Corrected in the Plugin design on 2026-10-01; complete document approval remains pending.

**Design:** PLG-REQ-056 calls the loaded result portable, alongside the old blanket live-state restriction.

**Current V3:** Persistence.Plugin.load first checks the stored input for portability, then calls load/3 and validates its result against the live state schema. The reconstructed result can contain local values.

**V2 approach:** V2 on_checkpoint could keep, drop, or externalize Plugin state. on_restore could reconstruct an arbitrary Plugin value, including a runtime-specific value.

**Reconciliation:** The Plugin design now records the current contract.  Change the requirement to distinguish portable input from schema-valid reconstructed live output. State that reconstruction does not transfer process ownership or prove resource liveness.

**Evidence:** [docs/design/05_plugins/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/05_plugins/design.md); [lib/jido/persistence/plugin.ex:34](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/plugin.ex:34); [lib/jido/plugin.ex:494](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/plugin.ex#L494).

<a id="gap-021"></a>

### GAP-021: Keep the required after_commit/3 failure boundary

**Type:** Resolved API decision. **State:** Settled: user selected the current V3 hook contract.

**Design before review:** Topics 05, 06, and 08 largely described post-commit work only as Directive dispatch. Their design and alignment documents now include the required hook and its dependent timing rules.

**Current V3:** after_commit/3 runs in declaration order after commit/reply and before Directives, including unchanged-state commits. It receives committed owned state/version, returns :ok or error, and cannot change state or add Directives. Failure skips later hooks and Directives. Startup, restore, and direct cmd do not call it. No replay is promised.

**V2 approach:** V2 had two different hooks. Agent on_after_cmd/3 ran inside cmd after the strategy returned and before the AgentServer accepted the returned Agent. It could change the Agent and Directives, and its contract required a pure function without side effects. Plugin transform_result/3 changed only the Agent returned to a synchronous caller. The Server had already accepted its state and queued Directives; the transformed return did not replace Server state. A transform_result exception was logged, and later Plugin transforms continued with the prior value. Neither hook was a required notification of an exact committed revision before Directive execution. V2 had no after_commit/3 callback.

**User decision:** On 2026-10-01, after the V2 comparison, the user selected the current V3 rule. An implemented hook is required before Directives. Failure skips later hooks and Directives; the committed Agent, version, and caller result remain intact. Optional observation uses Telemetry. This explicit V3 decision overrides the V2 fallback rule.

**Reconciliation:** The Plugin design and alignment now state callback inputs, ordering, failure, operation limits, startup/restore exclusions, and no automatic replay. Commit and Server documents carry the dependent timing and Outcome rules under GAP-026/038/039. Existing code and test cases were inspected; no source change or new test run was required. Observability vocabulary correction remains GAP-055.

**Evidence:** [lib/jido/plugin.ex:66](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin.ex:66); [lib/jido/agent_server/plugin/commit.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/plugin/commit.ex:1); [lib/jido/agent_server/post_commit.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/post_commit.ex:1); [test/jido/agent_server/after_commit_test.exs:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/test/jido/agent_server/after_commit_test.exs:1); [V2 Agent hook contract](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent.ex#L354); [V2 command hook call](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent.ex#L925); [V2 Plugin caller-view contract](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/plugin.ex#L342); [V2 Server result handling](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server.ex#L1617); [V2 Plugin transform exception handling](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server.ex#L2556).

<a id="gap-022"></a>

### GAP-022: Give Scheduler requirements an actual definition and owner

**Type:** Document correction. **State:** Corrected in Plugin design and delivery ledger.

**Design before review:** Topic 05 said PLG-REQ-061–076 belonged to Scheduler but did not define them. Delivery marked the entire 001–076 range required. The owner design and Plugin ledger row now distinguish defined active IDs, retired IDs, and numeric holes.

**Current V3:** Scheduler is a concrete Plugin with owned portable cron state, runtime timers, generation metadata, pending durable occurrences, and commit-time acknowledgements.

**V2 approach:** V2 Jido.Scheduler owned live cron jobs and durable schedule manifests. It had no equivalent current pending-occurrence acknowledgement contract.

**Reconciliation:** Scheduler is defined in the existing Plugin design. Original PLG-REQ-061–076 declarations were recovered from commit c2825dfb144ce6ccf4223b9401adae84b7c5bbd3. IDs 061–068 retain their occurrence and transient-timer intent; IDs 069–076 are retired under the explicit removal decision in GAP-023. New IDs 085–088 define the selected OTP scheduling boundary. The Plugin ledger row lists declared active IDs and retired IDs. Other release ledger corrections remain GAP-065.

**Evidence:** [Historical Scheduler requirements](https://github.com/agentjido/jido/blob/c2825dfb144ce6ccf4223b9401adae84b7c5bbd3/docs/design/05_plugins/design.md#L301); [docs/design/05_plugins/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/05_plugins/design.md); [lib/jido/plugin/scheduler.ex:3](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin/scheduler.ex:3); [docs/design/99_delivery/scope-ledger.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/99_delivery/scope-ledger.md); [lib/jido/scheduler.ex:10](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/scheduler.ex#L10).

<a id="gap-023"></a>

### GAP-023: Remove core Scheduler durable delivery

**Type:** Code change selected. **State:** Settled: removal selected; code cleanup pending.

**Design before review:** Generic recoverable-work requirements did not specify the current Scheduler policy, control route, timing options, or dormant schedules. The Plugin design now records an explicit target that removes pending business delivery from core Scheduler.

**Current V3:** One-shot schedules are transient. Durable recurring delivery keeps one pending occurrence per job, skips other slots, acknowledges with the business commit, and needs Agent persistence for loss recovery. Enqueue is a trusted, unauthenticated internal route. delivery_interval, delivery_timeout, retry_delay_ms, and time_scale have bounded contracts; a cron expression with no future slot is dormant.

**V2 approach:** V2 persisted cron definitions through Persist and separately rejected non-durable message values. Timers were runtime state. It did not provide current occurrence IDs, durable pending delivery, acknowledgement, or these Plugin options.

**User decision:** On 2026-10-01, the user rejected the extra delivery contract beyond OTP and selected removal of core Scheduler durable delivery. Keep OTP timers and mailbox delivery, restore saved recurring definitions for future ticks, and make no replay promise for missed occurrences. Remove saved pending business occurrences, delivery retries, enqueue controls, and business acknowledgement. No replacement durable-delivery package was requested.

**Reconciliation:** The target and code-removal scope are recorded in the Plugin design/alignment. Remove delivery-only APIs, helpers, pending fields, runtime workers/options, and their guide/example/test support. Preserve ordinary one-shot delivery, future recurring timers, saved definitions, and optional occurrence metadata, which does not itself provide retry. Check how older durable-delivery definitions are handled during restore. Existing source still implements the rejected feature; no implementation or fresh test run has been completed in this review. Generic application recovery contracts remain conditional and do not require this bundled Scheduler feature. GAP-028 still owns custom-checkpoint responsibility for other explicit recovery capabilities.

**Evidence:** [lib/jido/plugin/scheduler.ex:9](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin/scheduler.ex:9); [lib/jido/plugin/scheduler.ex:36](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin/scheduler.ex:36); [lib/jido/plugin/scheduler/wall_clock.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin/scheduler/wall_clock.ex:1); [test/jido/plugin/scheduler/occurrence_recovery_test.exs:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/test/jido/plugin/scheduler/occurrence_recovery_test.exs:1); [lib/jido/scheduler.ex:2](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/scheduler.ex#L2).

<a id="gap-024"></a>

### GAP-024: Document SensorManager instead of the removed V2 Sensor API

**Type:** Migration decision. **State:** Open.

**Design:** The generic Plugin seam does not identify SensorManager ownership or provide the V2 sensor migration contract.

**Current V3:** SensorManager stores the desired sensor set in owned portable state. Standard OTP children receive Init and send Signals. Runtime reconciliation rejects stale revisions and retries desired sensors.

**V2 approach:** V2 exposed Jido.Sensor behaviours, Sensor.Runtime, subscriptions, and AgentServer.SensorLifecycle. Plugins could declare sensor subscriptions directly.

**Reconciliation:** Add a capability and migration entry: replace V2 Sensor macros with standard OTP children and SensorManager start/stop Directives. Confirm that this intentional replacement overrides the V2 fallback rule.

**Evidence:** [lib/jido/plugin/sensor_manager.ex:3](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin/sensor_manager.ex:3); [lib/jido/plugin/sensor_manager/init.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin/sensor_manager/init.ex:1); [test/jido/plugin/sensor_manager_test.exs:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/test/jido/plugin/sensor_manager_test.exs:1); [lib/jido/sensor.ex:37](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/sensor.ex#L37); [lib/jido/agent_server/sensor_lifecycle.ex:1](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server/sensor_lifecycle.ex#L1).

<a id="gap-025"></a>

### GAP-025: Add a concise inventory of built-in capability contracts

**Type:** Document correction. **State:** Open.

**Design:** The design describes generic owner roles but omits a current inventory for Audit, Heartbeat, Bus, Scheduler, and SensorManager.

**Current V3:** Audit stores bounded selected domain records without a runtime. Heartbeat owns a timer and sends Signals. Bus separates manager/client resources and owner lifetime. Scheduler and SensorManager own desired state and runtime resources.

**V2 approach:** V2 provided HeartbeatSensor, BusSensor, Scheduler, and optional Memory/Thread/Identity Plugins. It had no current Audit Plugin or the same Bus manager/client design.

**Reconciliation:** Add a short owner table and links to module/guide contracts. Keep runtime values, selected audit facts, and recoverable work distinct. Do not copy every method into the design.

**Evidence:** [lib/jido/plugin/audit.ex:3](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin/audit.ex:3); [lib/jido/plugin/heartbeat.ex:3](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin/heartbeat.ex:3); [lib/jido/plugin/bus.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin/bus.ex:1); [lib/jido/sensors/heartbeat_sensor.ex:1](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/sensors/heartbeat_sensor.ex#L1); [lib/jido/sensors/bus_sensor.ex:1](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/sensors/bus_sensor.ex#L1).


## 06 Commit and effects

<a id="gap-026"></a>

### GAP-026: Correct settlement when a Turn has no Directives

**Type:** Document correction. **State:** Corrected in commit design and alignment.

**Design:** COMMIT-REQ-022 says a Turn without Directives settles at commit. The sequence omits Plugin hooks.

**Current V3:** Such a Turn can still run after_commit/3 and fail or time out afterward. Actual sequence is required checkpoint, state/version replacement, reply, hooks, Directives, terminal settlement.

**V2 approach:** V2 updated Agent state and queued Directives in a GenServer. It had no current Turn Outcome or required after_commit stage.

**Reconciliation:** COMMIT-REQ-019/022/023/029 and the commit model now include required hooks. Empty-batch settlement waits for hooks; call success confirms commit and does not wait for settlement. The commit remains after hook failure. The alignment records current source and existing test evidence under the selected GAP-021 decision.

**Evidence:** [docs/design/06_commit-and-effects/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/06_commit-and-effects/design.md); [lib/jido/agent_server/turn.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/turn.ex:1); [lib/jido/agent_server/post_commit.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/post_commit.ex:1); [lib/jido/agent_server/state.ex:276](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server/state.ex#L276).

<a id="gap-027"></a>

### GAP-027: Limit nondurable checkpoint requirements to named instances

**Type:** Document correction. **State:** Open.

**Design:** COMMIT-REQ-016 states an in-instance checkpoint write for all nonpersistent commits. Server and runtime requirements correctly qualify a named instance.

**Current V3:** RuntimeCheckpoint.put stores a snapshot for a named instance. The fallback returns :ok without storage for a directly started Server with no instance.

**V2 approach:** V2 stored runtime relationships in RuntimeStore, but did not implement this V3 latest-commit restart checkpoint contract.

**Reconciliation:** Qualify COMMIT-REQ-016 with a named live instance. State the direct standalone Server recovery limit explicitly; do not create a hidden global store.

**Evidence:** [docs/design/06_commit-and-effects/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/06_commit-and-effects/design.md); [lib/jido/agent_server/runtime_checkpoint.ex:60](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/runtime_checkpoint.ex:60); [lib/jido/agent_server/state.ex:256](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server/state.ex#L256).

<a id="gap-028"></a>

### GAP-028: Resolve recoverable work with opaque custom checkpoints

**Type:** API decision. **State:** Open.

**Design:** COMMIT-REQ-039 and DEC-006 require preservation of every field needed by a recoverable capability. PERS-REQ-043 preserves the initial custom-callback bypass.

**Current V3:** A custom Agent checkpoint owns its complete opaque payload. Core checks shape, revision, and portability but bypasses Plugin dump/load and cannot infer whether capability-owned recovery intent was omitted. Pending Scheduler delivery is an existing example selected for removal in GAP-023; its removal does not resolve the general custom-checkpoint ownership question.

**V2 approach:** V2 generated checkpoints ran Plugin keep/drop/externalize callbacks. Persist also enforced Thread pointers and cron manifests. An overridden custom callback therefore had capability-specific composition around it.

**Reconciliation:** Decide whether recovery is an application obligation for opaque callbacks, a capability-owned acceptance rule, or a future composed checkpoint contract. Recommended: document the current obligation and require capability-specific restore proof; do not claim automatic preservation.

**Evidence:** [docs/design/06_commit-and-effects/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/06_commit-and-effects/design.md); [docs/design/07_persistence/design.md:224](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/07_persistence/design.md:224); [lib/jido/agent/checkpoint.ex:21](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/checkpoint.ex:21); [lib/jido/persistence/checkpoint.ex:14](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/checkpoint.ex:14); [lib/jido/agent.ex:1075](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent.ex#L1075); [lib/jido/persist.ex:366](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/persist.ex#L366).


## 07 Persistence

<a id="gap-029"></a>

### GAP-029: Replace format-1/2 read promises with format-3-only behavior

**Type:** Migration decision. **State:** Open.

**Design:** PERS-REQ-039 and cross-seam inventories promise legacy outer records. Overview and delivery say unnamed format 2 and older format 1 remain readable.

**Current V3:** Persistence.Record accepts and writes outer format 3 only. Agent checkpoint envelopes independently use version 2. Other Store record owners can have different formats.

**V2 approach:** V2 stored version-1 checkpoint maps through Jido.Persist and Jido.Storage. Its format is not a V3 outer format-1 record. There is no direct compatible current reader.

**Reconciliation:** Confirm format-3-only support and retire old live-read promises. Define an offline migration and unsupported downgrade boundary. Keep Agent checkpoint version, outer Agent record format, and Topology record format separate.

**Evidence:** [docs/design/07_persistence/design.md:210](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/07_persistence/design.md:210); [lib/jido/persistence/record.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/record.ex:1); [lib/jido/agent/checkpoint.ex:11](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/checkpoint.ex:11); [lib/jido/persist.ex:388](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/persist.ex#L388).

<a id="gap-030"></a>

### GAP-030: Confirm stable namespace as a durable Agent prerequisite

**Type:** Migration decision. **State:** Open.

**Design:** The design retains unnamed module-based compatibility storage. Instance docs permit unnamed local operation but do not clearly separate durable activation.

**Current V3:** Durable Agent identity requires a nonempty stable namespace and valid Ref partition/ID. Missing namespace returns :stable_namespace_required. Local Agents can still use unnamed instances.

**V2 approach:** V2 required no namespace for checkpoint storage. It derived {agent_module, agent_id} keys.

**Reconciliation:** Confirm mandatory namespaces for durable Agent work as a V3 break. Provide configuration and import examples. Decide whether the raw prerequisite error stays public or is converted under GAP-053.

**Evidence:** [lib/jido/persistence/identity.ex:11](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/identity.ex:11); [docs/design/09_jido-instance/design.md:226](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/09_jido-instance/design.md:226); [lib/jido/persist.ex:629](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/persist.ex#L629).

<a id="gap-031"></a>

### GAP-031: Remove unsupported dual-key reads and collision gates

**Type:** Migration decision. **State:** Open.

**Design:** ID-REQ-027/028, PERS-REQ-040/041, instance alignment, package alignment, and delivery promise legacy/stable dual reads, collision detection, rewrite, and rollback rules.

**Current V3:** Current identity derives one Ref key. There is no legacy-key fallback, simultaneous-key lookup, or automatic rewrite.

**V2 approach:** V2 used only module-dependent checkpoint keys. It did not implement a Ref cutover or collision gate. Separate V2 decoding/conversion is necessary.

**Reconciliation:** Remove these current-runtime promises if format-3-only is retained. Document offline import with separate keys and backup-based rollback. Do not label an absent migration reader implemented.

**Evidence:** [docs/design/03_agent-identity/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/03_agent-identity/design.md); [docs/design/07_persistence/design.md:213](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/07_persistence/design.md:213); [lib/jido/persistence/identity.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/identity.ex:1); [docs/design/99_delivery/compatibility-register.md:34](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/99_delivery/compatibility-register.md:34); [lib/jido/persist.ex:629](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/persist.ex#L629).

<a id="gap-032"></a>

### GAP-032: Document opaque conditional-write tokens

**Type:** Document correction. **State:** Open.

**Design:** PERS-REQ-012/014 and PERS-DEC-007 specify exact bytes and explicitly reject opaque version tokens. The seam-12 adapter protocol omits token reads.

**Current V3:** Adapters can return {:ok, bytes, token}. Store.read returns bytes plus a write condition. CAS can accept :not_found, exact bytes, or {:token, token}. Tokens are key/location-specific and are not leases.

**V2 approach:** V2 checkpoint writes were unconditional overwrite operations. Thread journals had expected_rev concurrency controls, but these were not checkpoint byte CAS or opaque storage tokens.

**Reconciliation:** Update the adapter condition/result contract and tests. Preserve the distinction between byte equality and token equality. Document S3 use and confirmed conflict/rejection versus indeterminate writes.

**Evidence:** [docs/design/07_persistence/design.md:110](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/07_persistence/design.md:110); [lib/jido/persistence/adapter.ex:22](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/adapter.ex:22); [lib/jido/persistence/adapter_ops.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/adapter_ops.ex:1); [lib/jido/storage.ex:43](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/storage.ex#L43).

<a id="gap-033"></a>

### GAP-033: Assign the shared Store API a public contract

**Type:** Document correction. **State:** Open.

**Design:** The design scopes storage almost entirely to Agent records. Store is missing from the public success/protocol inventory.

**Current V3:** Persistence.Store opens validated adapter configuration, reads binary values with write conditions, and classifies CAS outcomes. It owns no Agent keys, revisions, tombstones, or lifecycle policy. Topology also uses it.

**V2 approach:** V2 Jido.Storage combined semantic checkpoint storage and Thread journals. It had no record-neutral validated byte Store.

**Reconciliation:** Document Store in topic 07 and register its raw results in topic 12. Assign record meaning to each consumer. Do not impose Agent format 3 or namespace rules on every Store consumer.

**Evidence:** [lib/jido/persistence/store.ex:3](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/store.ex:3); [lib/jido/topology/controller/target_store.ex:5](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/topology/controller/target_store.ex:5); [lib/jido/storage.ex:3](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/storage.ex#L3).

<a id="gap-034"></a>

### GAP-034: Update the adapter inventory and backend limits

**Type:** Document correction. **State:** Open.

**Design:** The recorded backend inventory lists ETS, File, Redis, Ecto, and Bedrock, without current Mnesia and S3 contracts.

**Current V3:** Seven adapters exist. Mnesia requires an existing set table, uses transactions/write locks, rejects local_content and nested transactions, and leaves table/recovery policy to the host. S3 requires a host request_fn and bucket, bounds objects to 5,000,000 bytes, verifies SHA-256 checksums, uses conditional writes/key-bound tokens, and requires writes without automatic retry or redirects.

**V2 approach:** V2 shipped ETS, File, and Redis checkpoint/journal adapters. It had no Jido Mnesia, S3, Ecto, or Bedrock checkpoint adapter equivalent in the checked tag.

**Reconciliation:** Add all seven adapters with atomicity mechanism, client ownership, limitations, and evidence type. Do not equate local/mock tests with external service proof.

**Evidence:** [lib/jido/persistence/mnesia.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/mnesia.ex:1); [lib/jido/persistence/s3.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/s3.ex:1); [test/jido/persistence/mnesia_disk_restart_test.exs:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/test/jido/persistence/mnesia_disk_restart_test.exs:1); [test/jido/persistence/s3_test.exs:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/test/jido/persistence/s3_test.exs:1); [lib/jido/storage.ex:9](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/storage.ex#L9).

<a id="gap-035"></a>

### GAP-035: Retain or approve migration of raw storage failures

**Type:** API decision. **State:** Open.

**Design:** PERS-REQ-021 proposes later conversion to persistence-owned codes. ERR-REQ-012 preserves raw adapter reasons until that migration is approved.

**Current V3:** Agent Persistence and Store still return raw not-found, conflict, rejection, configuration, record, and indeterminate controls. Adapter faults and malformed replies use owner conversion paths.

**V2 approach:** V2 used raw controls and wrapped callback faults in checkpoint_callback_failed/restore_callback_failed tuples. It had no closed persistence error-code registry.

**Reconciliation:** Recommended under the V2 fallback: retain current documented controls for now, expand the protocol inventory, and keep a future conversion explicitly pending. Do not treat PERS-REQ-021 as an implemented code set.

**Evidence:** [docs/design/07_persistence/design.md:144](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/07_persistence/design.md:144); [docs/design/12_errors-and-contracts/design.md:89](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/12_errors-and-contracts/design.md:89); [lib/jido/persistence/store.ex:33](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/store.ex:33); [lib/jido/persist.ex:625](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/persist.ex#L625).

<a id="gap-036"></a>

### GAP-036: Keep Bedrock service proof separate from adapter implementation

**Type:** Evidence update. **State:** Open.

**Design:** The alignment cites an absent Bedrock integration test path and historical beta service evidence.

**Current V3:** The adapter is implemented. Real Bedrock service and snapshot profiles are paused/skipped. Fake transaction tests do not establish cold recovery or service durability.

**V2 approach:** V2 has no Bedrock adapter equivalent. Its File/Redis service model cannot prove Bedrock behavior.

**Reconciliation:** Replace the absent test reference with current profile paths. Retain the unproved result and user pause. No parked upstream work is included in the core implementation queue; release scope needs a separate decision.

**Evidence:** [docs/design/07_persistence/alignment.md:133](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/07_persistence/alignment.md:133); [lib/jido/persistence/bedrock.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/bedrock.ex:1); [docs/design/99_delivery/evidence.md:49](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/99_delivery/evidence.md:49); [lib/jido/storage.ex:9](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/storage.ex#L9).


## 08 Agent Server

<a id="gap-037"></a>

### GAP-037: Update completed initial-durability follow-up claims

**Type:** Evidence update. **State:** Open.

**Design:** Some briefing/open-work text still calls initial active records or readiness publication later work.

**Current V3:** Startup loads/validates restore state, starts provisional Plugin runtimes, waits for readiness, confirms create-only revision zero when needed, then publishes ready. Startup failure cleans provisional resources.

**V2 approach:** V2 could thaw managed Agents through lifecycle/InstanceManager paths. It had no current V3 confirmed initial CAS-before-readiness contract.

**Reconciliation:** Keep the implemented sequence and replace stale open-work/evidence rows. Distinguish ready lookup from reserved starting registrations.

**Evidence:** [docs/design/06_commit-and-effects/README.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/06_commit-and-effects/README.md); [lib/jido/agent_server/server_lifecycle.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/server_lifecycle.ex:1); [lib/jido/agent_server/registry_worker.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/registry_worker.ex:1); [lib/jido/agent_server/lifecycle/keyed.ex:1](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server/lifecycle/keyed.ex#L1).

<a id="gap-038"></a>

### GAP-038: Add after_commit to Outcome stages

**Type:** Document correction. **State:** Corrected in Server design and alignment.

**Design:** The Server Outcome description lists prepare, execute, finalize, commit, and directive.

**Current V3:** Outcome permits six stages: prepare, execute, finalize, commit, after_commit, and directive. A hook failure is a committed failure at after_commit.

**V2 approach:** V2 has no Jido.Agent.Turn.Outcome. GenServer status/results were not equivalent terminal settlement values.

**Reconciliation:** The Server model and alignment now include all six current Outcome stages and a committed after_commit failure example. Private evaluator stages remain separate from public Outcome and semantic telemetry vocabularies. Semantic stage correction remains GAP-055.

**Evidence:** [docs/design/08_agent-server/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/08_agent-server/design.md); [lib/jido/agent/turn/outcome.ex:13](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/turn/outcome.ex:13); [test/jido/agent_server/after_commit_test.exs:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/test/jido/agent_server/after_commit_test.exs:1); [lib/jido/agent_server/status.ex:1](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server/status.ex#L1).

<a id="gap-039"></a>

### GAP-039: Document hook timeout, directing phase, and reentry

**Type:** Document correction. **State:** Corrected in Server design and alignment.

**Design:** Time-limit and reentry tables describe admission, execution, and Directives, without hook operations.

**Current V3:** Hooks run as owned Tasks during directing. Each uses finite directive_timeout, or 5,000 ms when that option is infinity. Same-activation synchronous reentry returns reentrant_commit. Cancellation is too late after commit.

**V2 approach:** V2 had caller timeouts and queued Directive execution. It had no current hook Task timeout or committed-hook reentry boundary.

**Reconciliation:** The Server model, controls, timeout table, shutdown requirement, and SRV-REQ-077 now include owned hook work, its finite timeout fallback, late cancellation, and same-activation reentry. The public hook reentry result is documented as {:error, :reentrant_commit}. The consolidated error/control inventory remains GAP-053.

**Evidence:** [lib/jido/plugin.ex:74](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin.ex:74); [lib/jido/agent_server/admission.ex:82](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/admission.ex:82); [lib/jido/agent_server/post_commit.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/post_commit.ex:1); [lib/jido/agent_server.ex:331](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server.ex#L331).

<a id="gap-040"></a>

### GAP-040: Clarify copied local handles in runtime checkpoints

**Type:** Document correction. **State:** Open.

**Design:** SRV-REQ-003 and RT-REQ-027 ban runtime handles from every checkpoint. They do not distinguish private Server fields from local values held in Agent state.

**Current V3:** Nondurable RuntimeCheckpoint copies the complete Agent for abnormal restart within a live named instance. A copied handle may be stale; it does not recreate resources, transfer ownership, or install monitors. Durable checkpoints use separate portability rules.

**V2 approach:** V2 kept Server task/timer fields privately but also injected runtime-related fields into Agent state. It did not provide the current V3 snapshot recovery guarantee.

**Reconciliation:** Document the copied-value limitation. Keep application resource reconstruction in Plugin runtime or host code. Keep Server private process state out of Agent values.

**Evidence:** [docs/design/08_agent-server/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/08_agent-server/design.md); [docs/design/10_runtime-topology/design.md:161](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/10_runtime-topology/design.md:161); [lib/jido/agent_server/runtime_checkpoint.ex:4](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/runtime_checkpoint.ex:4); [lib/jido/agent_server/state.ex:256](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server/state.ex#L256).

<a id="gap-041"></a>

### GAP-041: Remove the unavailable module-key upgrade mode

**Type:** Document correction. **State:** Open.

**Design:** SRV-REQ-074 defines rejection of cross-module upgrades under a module-dependent compatibility key.

**Current V3:** Durable activation already requires stable namespace identity. Upgrade uses that storage model; no legacy module-key activation mode remains.

**V2 approach:** V2 persistence keys included Agent module. The checked Server has no equivalent current quiescent definition-migration API.

**Reconciliation:** Retire the unreachable legacy-key condition if GAP-030/031 remain. Keep complete migration validation, unchanged Plugin contract, one revision increment, and no private-state hot migration.

**Evidence:** [docs/design/08_agent-server/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/08_agent-server/design.md); [lib/jido/agent_server/upgrade.ex:43](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/upgrade.ex:43); [lib/jido/persist.ex:629](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/persist.ex#L629).

<a id="gap-042"></a>

### GAP-042: Describe upgrade and cancellation raw controls

**Type:** Document correction. **State:** Open.

**Design:** The raw-control inventory uses broad child/inspection categories but omits several new operation-specific controls.

**Current V3:** Upgrade can return invalid_upgrade_result, invalid_migrated_state, invalid_migration_result, plugin_contract_changed, and stable_namespace_required. Hooks add reentrant_commit. Converted fault codes have the registry gap in GAP-050.

**V2 approach:** V2 returned raw lifecycle, timeout, and callback controls. It had no current definition replacement or cancellable V3 Turn API.

**Reconciliation:** Record each owned control family and its meaning. Decide normalization only after the operation contract is selected. Keep the missing converted codes separate from intentional raw controls.

**Evidence:** [lib/jido/agent_server/upgrade.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/upgrade.ex:1); [lib/jido/agent_server/cancellation.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/cancellation.ex:1); [docs/design/12_errors-and-contracts/design.md:218](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/12_errors-and-contracts/design.md:218); [lib/jido/agent_server.ex:331](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server.ex#L331).


## 09 Jido instance

<a id="gap-043"></a>

### GAP-043: Correct unnamed local and namespaced durable behavior

**Type:** Document correction. **State:** Open.

**Design:** Instance briefing/alignment retain dual-key persistence and collision handling.

**Current V3:** Optional namespace supports ordinary local Agents. Ref-first operations require a namespace. Durable Agent work also requires a stable namespace, regardless of whether the caller uses a PID/ID facade.

**V2 approach:** V2 used named local instances and ID/partition lookup without a durable namespace. Its generated facade delegated snapshot persistence to configured storage.

**Reconciliation:** Update the instance table, errors, and examples using GAP-030/031. Retain per-Agent persistence precedence, five children, host-owned clients, and public ID/PID operations.

**Evidence:** [docs/design/09_jido-instance/README.md:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/09_jido-instance/README.md:1); [lib/jido/instance/options.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/instance/options.ex:1); [lib/jido/instance/ref_facade.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/instance/ref_facade.ex:1); [lib/jido/persistence/identity.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/identity.ex:1); [lib/jido.ex:206](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido.ex#L206).


## 10 Runtime topology

<a id="gap-044"></a>

### GAP-044: Update worker inventory and Plugin owner terminology

**Type:** Document correction. **State:** Open.

**Design:** Runtime tables refer to separate facet authoring and list admission, execution, Directive, readiness, and error-policy workers only.

**Current V3:** Four core owners execute callbacks from one Plugin module. Required after_commit work also uses owned Tasks, participates in shutdown, and cannot outlive its activation.

**V2 approach:** V2 had a four-child base instance tree, optional worker pools, GenServer Directive queues, cron jobs, and sensor runtimes. It did not use the V3 five-child tree and Plugin wrapper ownership protocol.

**Reconciliation:** Update task and Plugin diagrams while keeping the implemented five-child tree, peer Agent Servers, temporary wrappers, permanent declared roots, logical child handles, and exact-node/no-fallback rules.

**Evidence:** [docs/design/10_runtime-topology/design.md:123](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/10_runtime-topology/design.md:123); [lib/jido/agent_server/task_support.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/task_support.ex:1); [lib/jido/agent_server/plugin_child.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/plugin_child.ex:1); [lib/jido.ex:623](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido.ex:623); [lib/jido.ex:370](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido.ex#L370).


## 11 Topology control plane

<a id="gap-045"></a>

### GAP-045: Define accepted-target storage and restore

**Type:** Document correction. **State:** Open.

**Design:** The design covers additive update and retained placements but does not define the current target record and restore boundary. The existing warning about distributed authority remains correct.

**Current V3:** TargetStore saves accepted definition/input, placements, revision, and pending move. Without an adapter it uses RuntimeStore. With inherited persistence it uses Store and a separate format-1 topology record. Its key uses the namespace when present and otherwise the instance atom name. This is local Controller state, not cluster authority or an Agent Ref record.

**V2 approach:** V2 Pod stored canonical topology/version under its owned __pod__ Agent state, then persisted the Pod through ordinary Agent checkpointing. It did not use a separate V3 Controller target record.

**Reconciliation:** Document target key, lifetime, identity and plan-extension compatibility checks, restore rejection, independent record format, and required write behavior. Explain the instance-name fallback and its rename/migration effect. Do not remove the distributed-authority non-guarantee.

**Evidence:** [docs/design/11_topology-control-plane/design.md:462](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/11_topology-control-plane/design.md:462); [lib/jido/topology/controller/target_store.ex:10](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/topology/controller/target_store.ex:10); [test/jido/topology/controller_target_store_test.exs:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/test/jido/topology/controller_target_store_test.exs:1); [lib/jido/pod.ex:152](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/pod.ex#L152).

<a id="gap-046"></a>

### GAP-046: Define pending move and failed target-write recovery

**Type:** Document correction. **State:** Open.

**Design:** Exact-node placement requirements describe stopping and restarting an owned Agent, but do not specify the current saved pending move or target CAS failure rules.

**Current V3:** TargetStore writes a pending_move before placement completion and later clears it. It uses a revision and atomic storage condition for durable updates. Runtime recovery consumes the saved target and placement state.

**V2 approach:** V2 Pod mutation plans stopped/started dependency waves and recorded a mutation report in Pod state. That is not the current saved exact-placement transition.

**Reconciliation:** Document accepted intent, last confirmed phase, failure handling, restart behavior, and duplicate operation limits. Link target-store and placement tests; make no general transactional multi-Agent or fencing claim.

**Evidence:** [lib/jido/topology/controller/target_store.ex:28](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/topology/controller/target_store.ex:28); [lib/jido/topology/controller/runtime.ex:30](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/topology/controller/runtime.ex:30); [test/jido/topology/controller_target_store_test.exs:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/test/jido/topology/controller_target_store_test.exs:1); [lib/jido/pod/runtime.ex:84](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/pod/runtime.ex#L84).

<a id="gap-047"></a>

### GAP-047: Refresh ownership cleanup and settlement evidence

**Type:** Evidence update. **State:** Open.

**Design:** Earlier alignment cleanup evidence does not fully identify the current Owner wait, remote-member tracking, and ownership settlement event.

**Current V3:** Owner tracks local/remote members, waits for local OTP cleanup, and emits an ownership settlement result. Remote uncertainty remains distinct from confirmed termination.

**V2 approach:** V2 Pod and parent bindings tracked logical ownership and reconciliation. They did not produce the current V3 Topology ownership settlement contract.

**Reconciliation:** Record exactly what cleanup confirms, the remote limit, and the event. Keep application supervision above Controller and no distributed fencing claim.

**Evidence:** [lib/jido/topology/controller/owner.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/topology/controller/owner.ex:1); [lib/jido/telemetry/topology.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/telemetry/topology.ex:1); [docs/design/11_topology-control-plane/alignment.md:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/11_topology-control-plane/alignment.md:1); [lib/jido/pod/runtime.ex:1](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/pod/runtime.ex#L1).

<a id="gap-048"></a>

### GAP-048: Bring Topology acceptance coverage through requirement 101

**Type:** Evidence update. **State:** Open.

**Design:** Design declares TOP-REQ-077–101 for root authoring, lifecycle Signals, placement, Codec, resources, and lifecycle Signal modules. Alignment and delivery ranges stop earlier.

**Current V3:** The current code implements those local additions, including Codec version 2, all-components-ready startup, resource ownership, exact node selection, and custom lifecycle Signal modules.

**V2 approach:** V2 Pod used its own module keyword topology and runtime/mutation model. It had no equivalent current Codec, root blocks, or lifecycle module family.

**Reconciliation:** Add current owner evidence and dispositions for every declared local ID. Retire Builder from TOP-REQ-059. Preserve any external requirements as external.

**Evidence:** [docs/design/11_topology-control-plane/design.md:393](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/11_topology-control-plane/design.md:393); [docs/design/11_topology-control-plane/design.md:470](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/11_topology-control-plane/design.md:470); [lib/jido/topology.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/topology.ex:1); [lib/jido/topology/signal/operation_started.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/topology/signal/operation_started.ex:1); [lib/jido/pod.ex:59](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/pod.ex#L59).

<a id="gap-049"></a>

### GAP-049: Keep distributed reference contracts out of the core backlog

**Type:** Scope correction. **State:** Outside core; no implementation requested.

**Design:** TOP-REQ-006–058 and 061 describe membership, leases/epochs, fencing, failover, rebalance, and operator policy. ID-REQ-021/022 also include external delivery/placement targets.

**Current V3:** Core implements local Controller operations and explicit known-node primitives. It has no general cluster membership, automatic placement, exclusive ownership, transport, or durable inbox contract.

**V2 approach:** V2 Pod and child placement did not provide the required V3 epoch fencing or cluster-exclusive authority either. They are not a solved baseline for these requirements.

**Reconciliation:** Keep these rows deferred/external and visible in coverage. Do not include them in the active core reconciliation queue. No parked upstream or external package work is requested.

**Evidence:** [docs/design/11_topology-control-plane/design.md:101](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/11_topology-control-plane/design.md:101); [docs/design/11_topology-control-plane/design.md:101](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/11_topology-control-plane/design.md:101); [docs/design/03_agent-identity/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/03_agent-identity/design.md); [lib/jido/topology/controller.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/topology/controller.ex:1); [lib/jido/pod/runtime.ex:1](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/pod/runtime.ex#L1).


## 12 Errors and contracts

<a id="gap-050"></a>

### GAP-050: Register the three emitted cancellation and upgrade codes

**Type:** Confirmed code gap. **State:** Open.

**Design:** ERR-REQ-003 and the alignment claim a closed registry covering all literal Jido conversion codes.

**Current V3:** Source emits agent_exec_cancel_failed, agent_upgrade_failed, and agent_state_migration_failed, but Error.stable_codes/0 lists none. Error.code/1 returns nil for all three and semantic projection omits them.

**V2 approach:** V2 had the same broad Splode classes/types but no stable_codes/0 or code/1 registry contract. It cannot supply missing V3 registry entries.

**Reconciliation:** Add the three codes, their type declaration and triggers, real failure-path tests, and design registry rows. Keep their execution class. This repairs an implemented V3 contract.

**Evidence:** [docs/design/12_errors-and-contracts/design.md:54](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/12_errors-and-contracts/design.md:54); [lib/jido/error.ex:145](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/error.ex:145); [lib/jido/agent_server/cancellation.ex:132](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/cancellation.ex:132); [lib/jido/agent_server/upgrade.ex:33](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/upgrade.ex:33); [lib/jido/agent_server/upgrade.ex:66](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/upgrade.ex:66); [lib/jido/error.ex:1](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/error.ex#L1).

<a id="gap-051"></a>

### GAP-051: Resolve the universal code rule for ordinary validation errors

**Type:** API decision. **State:** Open.

**Design:** ERR-REQ-003 says each Jido-owned failure conversion uses a registered code. That is broader than the selected callback/runtime registry.

**Current V3:** Ordinary Ref, Agent, state-schema, and other validation errors can have details without a top-level code. A fresh Ref.new(%{}) returns a Jido ValidationError and Error.code/1 returns nil. This is separate from GAP-050 unregistered literal codes.

**V2 approach:** V2 ordinary ValidationError helpers did not require stable codes. Callers used class, fields, details, or raw controls.

**Reconciliation:** Decide whether to narrow ERR-REQ-003 to registered program conversions or add codes for all owned validation failures. Recommended under V2 fallback: keep optional codes for ordinary validation and register every explicit program code.

**Evidence:** [docs/design/12_errors-and-contracts/design.md:54](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/12_errors-and-contracts/design.md:54); [lib/jido/agent/ref.ex:64](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/ref.ex:64); [lib/jido/error.ex:405](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/error.ex:405); [lib/jido/error.ex:543](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/error.ex:543); [lib/jido/error.ex:328](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/error.ex#L328).

<a id="gap-052"></a>

### GAP-052: Update public shaped values and internal-type inventories

**Type:** Document correction. **State:** Open.

**Design:** The consolidated inventory omits the public Plugin.Commit input and shared Store results, and retains earlier owner/facet descriptions.

**Current V3:** Commit is a read-only hook input. Store exposes configuration and condition results. Spec/Manifest values are internal implementation data. Current generated Signal helpers do not expose old interface records.

**V2 approach:** V2 exposed Plugin.Spec/Instance, Server.Status, and strategy snapshots under a different API. It had no current Commit or byte Store.

**Reconciliation:** Classify new current values by owner, public purpose, validation, result shape, and compatibility. Remove absent interface entries. Do not promote internal Spec fields into a public contract.

**Evidence:** [docs/design/12_errors-and-contracts/design.md:244](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/12_errors-and-contracts/design.md:244); [lib/jido/agent_server/plugin/commit.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/plugin/commit.ex:1); [lib/jido/persistence/store.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/store.ex:1); [lib/jido/plugin/spec.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin/spec.ex:1); [lib/jido/plugin/spec.ex:1](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/plugin/spec.ex#L1).

<a id="gap-053"></a>

### GAP-053: Expand the protocol-control registry to actual results

**Type:** Document correction. **State:** Open.

**Design:** The registry omits token get results, Store conditions/errors, namespace-required storage controls, hook reentry, and current Topology update/placement/target results. Some text still says fixed-target local meaning.

**Current V3:** Those values are used by current public boundaries. Returned application callback reasons remain exact; they must not be assigned inferred Jido codes.

**V2 approach:** V2 used extensive raw OTP, lookup, lifecycle, and storage controls. It had no current cross-owner protocol registry.

**Reconciliation:** Record result shape and meaning by owner. Link GAP-035, GAP-039, and GAP-042. Keep any future normalization migration pending instead of changing results in this report.

**Evidence:** [docs/design/12_errors-and-contracts/design.md:218](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/12_errors-and-contracts/design.md:218); [lib/jido/persistence/adapter.ex:27](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/adapter.ex:27); [lib/jido/persistence/store.ex:29](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/store.ex:29); [lib/jido/agent_server/admission.ex:82](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/admission.ex:82); [lib/jido/storage.ex:58](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/storage.ex#L58).


## 13 Observability

<a id="gap-054"></a>

### GAP-054: Make the event-family inventories agree

**Type:** Document correction. **State:** Open.

**Design:** The design lists eleven semantic families, including Plugin notification and ownership settlement. Earlier README/alignment counts and evidence still describe nine.

**Current V3:** Semantic Agent, persistence, Topology, hook, ownership, and Scheduler events are present. Shared Store adds a further boundary in GAP-057.

**V2 approach:** V2 Observe emitted lifecycle/action/custom spans and legacy Server telemetry. It had no equivalent V3 committed Turn/settlement catalog.

**Reconciliation:** Use one catalog and derive briefing/counts from it. Document implemented families, owner, event shape, measurements, and test evidence without making historical counts current.

**Evidence:** [docs/design/13_observability/design.md:46](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/13_observability/design.md:46); [docs/design/13_observability/alignment.md:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/13_observability/alignment.md:1); [lib/jido/telemetry/agent.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/telemetry/agent.ex:1); [lib/jido/observe.ex:76](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/observe.ex#L76).

<a id="gap-055"></a>

### GAP-055: Add after_commit to the semantic stage vocabulary

**Type:** Document correction. **State:** Open.

**Design:** The design stage table lists evaluate, commit, and directive only.

**Current V3:** Semantic.normalize accepts after_commit. Hook spans and settlement projections use it.

**V2 approach:** V2 had no matching semantic stage vocabulary or required hook boundary.

**Reconciliation:** Add the stage and its collapse/projection rules. Keep it separate from prepare/execute/finalize Outcome stages and private Runner failure stages.

**Evidence:** [docs/design/13_observability/design.md:81](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/13_observability/design.md:81); [lib/jido/telemetry/semantic.ex:13](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/telemetry/semantic.ex:13); [lib/jido/observe.ex:1](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/observe.ex#L1).

<a id="gap-056"></a>

### GAP-056: Add Plugin owner module fields to the allowlist table

**Type:** Document correction. **State:** Open.

**Design:** Metadata tables omit plugin_module and facet_module accepted by current code.

**Current V3:** Both are bounded module atoms used by hook and Plugin events. Private values, complete state, payloads, and options remain excluded.

**V2 approach:** V2 allowed more general span metadata and correlation enrichment. It did not use the same closed V3 allowlist.

**Reconciliation:** Document these module fields and their event use. Keep them out of default metric tags, along with other module/identity values.

**Evidence:** [docs/design/13_observability/design.md:90](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/13_observability/design.md:90); [lib/jido/telemetry/semantic.ex:10](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/telemetry/semantic.ex:10); [lib/jido/telemetry/semantic.ex:10](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/telemetry/semantic.ex:10); [lib/jido/observe.ex:89](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/observe.ex#L89).

<a id="gap-057"></a>

### GAP-057: Add shared Store events and consumer policy

**Type:** Document correction. **State:** Open.

**Design:** The eleven-family catalog describes Agent persistence operation events, not the newer generic Store family.

**Current V3:** Store emits [:jido, :persistence, :store, event] through Semantic.with_span for load and CAS, with adapter, operation, and status. It excludes keys, values, tokens, and options. Semantic spans reach the optional OpenTelemetry mapping. The current built-in metric list and logger attachment omit the Store family.

**V2 approach:** V2 storage adapters had no matching record-neutral Store semantic family.

**Reconciliation:** Add the family, supported terminal behavior, and actual OpenTelemetry mapping. Decide whether to add default Store metrics/logger attachment or retain those exclusions. Keep the code and catalog aligned for each consumer.

**Evidence:** [lib/jido/persistence/store.ex:141](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/store.ex:141); [lib/jido/telemetry.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/telemetry.ex:1); [lib/jido/telemetry/open_telemetry.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/telemetry/open_telemetry.ex:1); [docs/design/13_observability/design.md:12](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/13_observability/design.md:12); [lib/jido/storage.ex:1](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/storage.ex#L1).

<a id="gap-058"></a>

### GAP-058: Correct legacy Observe and OpenTelemetry compatibility claims

**Type:** Migration decision. **State:** Open.

**Design:** Topic 13 removes legacy Observe and implements an optional API bridge, but Overview, package/delivery records still retain legacy observation or defer the bridge.

**Current V3:** Jido.Observe and the old Server event family are absent. The semantic boundary and optional API-only OpenTelemetry mapping exist. Host owns SDK/exporters.

**V2 approach:** V2 provided Observe.Tracer, configurable tracer callbacks, and legacy events. This is an intentional V3 replacement with a telemetry/API bridge.

**Reconciliation:** Keep the current implementation as canonical. Provide explicit event/tracer migration and remove contradictory retention/deferred bridge claims from current candidate records. Preserve beta.1 records as history.

**Evidence:** [docs/design/13_observability/design.md:393](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/13_observability/design.md:393); [lib/jido/telemetry/open_telemetry.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/telemetry/open_telemetry.ex:1); [docs/design/99_delivery/compatibility-register.md:52](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/99_delivery/compatibility-register.md:52); [lib/jido/observe.ex:13](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/observe.ex#L13).


## 90 Package boundaries

<a id="gap-059"></a>

### GAP-059: Classify Store and local Topology target ownership

**Type:** Document correction. **State:** Open.

**Design:** The package seam correctly assigns Agent semantics and external policy, but its inventory still assumes storage is only Agent records and describes old Plugin facets.

**Current V3:** Persistence owns generic byte Store; Agent persistence owns Agent records; Topology owns its independent accepted-target record. Local target storage is in core and is not distributed desired-state authority.

**V2 approach:** V2 Storage coupled checkpoints and Thread journals. Pod desired topology lived in Pod-owned Agent state.

**Reconciliation:** Add current record-owner boundaries and one-module Plugin execution owners. Retain Action/Signal dependency direction and external cluster/transport/AI limits.

**Evidence:** [docs/design/90_package-boundaries/design.md:253](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/90_package-boundaries/design.md:253); [lib/jido/persistence/store.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/store.ex:1); [lib/jido/topology/controller/target_store.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/topology/controller/target_store.ex:1); [lib/jido/storage.ex:3](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/storage.ex#L3); [lib/jido/pod.ex:152](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/pod.ex#L152).

<a id="gap-060"></a>

### GAP-060: Make the V2-to-V3 public migration inventory explicit

**Type:** Migration decision. **State:** Open.

**Design:** Broad retained-public-API claims do not explain V2 command tuples/Strategies, NimbleOptions schemas, Sensor APIs, Persist/Storage, Pod, worker pools, Memory/Thread/Identity, or Observe replacements/removals.

**Current V3:** V3 uses Signal-to-Turn cmd/3, complete state Actions/Flows, static Zoi state schemas, callback Plugins, Persistence/Store, Topology.Controller, SensorManager, and semantic telemetry. Several V2 modules have no core equivalent.

**V2 approach:** The checked V2 tree includes those former public surfaces. Some have narrower V3 replacements; some have no direct counterpart. Builder is not one of those V2 surfaces.

**Reconciliation:** Create an explicit retained/changed/removed/external migration inventory inside existing owner documents. Under the user rule, use V2 when a specific API intent is unclear. Do not restore every former module or Strategy without a decision.

**Evidence:** [docs/design/90_package-boundaries/design.md:286](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/90_package-boundaries/design.md:286); [lib/jido/agent.ex:384](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent.ex:384); [lib/jido/plugin.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin.ex:1); [lib/jido/agent.ex:30](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent.ex#L30); [lib/jido/pod.ex:1](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/pod.ex#L1); [lib/jido/agent/worker_pool.ex:1](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent/worker_pool.ex#L1); [lib/jido/thread.ex:1](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/thread.ex#L1).


## 99 Delivery

<a id="gap-061"></a>

### GAP-061: Separate published beta.1 evidence from the current candidate

**Type:** Evidence update. **State:** Open.

**Design:** The four release records describe beta.1 commit 5413df11 and use Current local results headings. Current lib is 35c9644a.

**Current V3:** The release branch contains later public contract, storage, authoring, observation, and test changes. Historical counts and exceptions do not prove those changes.

**V2 approach:** V2 release artifacts and tag metadata establish an old version only. They do not supply V3 release approval or evidence.

**Reconciliation:** Preserve beta.1 evidence as historical. Add a clearly dated current-candidate section with exact commit, package sources, changed APIs, gates, and limits. No release approval is granted by this report.

**Evidence:** [docs/design/99_delivery/evidence.md:7](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/99_delivery/evidence.md:7); [docs/design/99_delivery/package-matrix.md:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/99_delivery/package-matrix.md:1); [mix.exs:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/mix.exs:1); [mix.exs:1](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/mix.exs#L1).

<a id="gap-062"></a>

### GAP-062: Record Git dependency pins and the Hex publication gate

**Type:** Release decision. **State:** Open.

**Design:** The package matrix and package alignment claim production dependencies have no Git/path sources.

**Current V3:** mix.exs pins Action 8e9b3f7 and Zoi ad24cc0 through Git. Signal uses Hex beta.4. These are immutable development sources, but normal Hex packaging rejects Git dependencies; the prior sync recorded that failure.

**V2 approach:** V2 used released Hex dependencies in its package configuration. Its versions cannot be mixed into V3 to bypass the current dependency gate.

**Reconciliation:** Update the current matrix. Before publication, select released compatible Action/Zoi versions and rerun exact-candidate package checks. Keep this publication blocker separate from local test compatibility.

**Evidence:** [mix.exs:367](/Users/mhostetler/Source/Jido/proj_jido_core/jido/mix.exs:367); [mix.exs:378](/Users/mhostetler/Source/Jido/proj_jido_core/jido/mix.exs:378); [docs/design/99_delivery/package-matrix.md:30](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/99_delivery/package-matrix.md:30); [mix.exs:387](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/mix.exs#L387).

<a id="gap-063"></a>

### GAP-063: Replace the obsolete floor failure with exact-commit evidence

**Type:** Evidence update. **State:** Open.

**Design:** Beta.1 records report Elixir 1.18/OTP 27 test compilation failure and proof only on the newer runtime.

**Current V3:** Prior release sync recorded passing floor checks and four successful CI runtime combinations at current HEAD. This report also used the floor for pure probes. It did not rerun the full suite or CI.

**V2 approach:** V2 had a separate declared Elixir floor and its own CI configuration. It does not establish V3 runtime compatibility.

**Reconciliation:** Record the saved passing results with exact commit/run links and commands. Keep the old beta.1 exception historical. Do not claim every OTP patch or new full-suite execution from this review.

**Evidence:** [docs/design/99_delivery/package-matrix.md:37](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/99_delivery/package-matrix.md:37); [tmp/local-change-commits/summary.md:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/tmp/local-change-commits/summary.md:1); [.github/workflows/ci.yml:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/.github/workflows/ci.yml:1); [mix.exs:14](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/mix.exs#L14).

<a id="gap-064"></a>

### GAP-064: Align release commands with current test categories

**Type:** Document correction. **State:** Open.

**Design:** DEL-REQ-014/015 use mix benchmarks and mix examples. Current aliases and CI use test.bench/test.examples and explicit core/property selections.

**Current V3:** mix test.all includes property, peer, benchmark, examples, authoring, and local system categories; services and fuzz are separate. mix quality includes core and generated properties. Current fuzz has corpus/report support.

**V2 approach:** V2 tests and aliases covered its own contracts; it has no current V3 property/fuzz requirement coverage or generated corpus baseline.

**Reconciliation:** Use executable current aliases and state what each selection includes/excludes. Add property and fuzz evidence/gates only at the agreed release scope. Do not claim fuzz passed because quality or test.all passed.

**Evidence:** [docs/design/99_delivery/design.md:86](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/99_delivery/design.md:86); [mix.exs:162](/Users/mhostetler/Source/Jido/proj_jido_core/jido/mix.exs:162); [mix.exs:163](/Users/mhostetler/Source/Jido/proj_jido_core/jido/mix.exs:163); [mix.exs:166](/Users/mhostetler/Source/Jido/proj_jido_core/jido/mix.exs:166); [.github/workflows/ci.yml:29](/Users/mhostetler/Source/Jido/proj_jido_core/jido/.github/workflows/ci.yml:29); [mix.exs:417](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/mix.exs#L417).

<a id="gap-065"></a>

### GAP-065: Replace closed ranges with the current requirement inventory

**Type:** Document correction. **State:** Open.

**Design:** Delivery stops Agent at 041, Topology at 076, omits newer OBS-058, includes retired/unassigned IDs, and treats PLG-061–076 as defined. Some OpenTelemetry rows remain deferred despite implementation.

**Current V3:** The extracted design declarations contain 835 unique topic requirement entries, including thirteen explicitly declared retired entries. Numeric holes and prose-only references are not active requirements. Current additions need exact dispositions.

**V2 approach:** V2 had no matching V3 EARS requirement ledger. Its tests cannot assign those dispositions.

**Reconciliation:** Use exact declared IDs and distinguish retired, external, implemented, decision, and evidence status. Audit prose-only IDs separately. Preserve IDs when correcting wording; retire removed behavior rather than reuse its number.

**Evidence:** [docs/design/99_delivery/scope-ledger.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/99_delivery/scope-ledger.md); [docs/design/01_agent/design.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/01_agent/design.md); [docs/design/11_topology-control-plane/design.md:470](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/11_topology-control-plane/design.md:470); [docs/design/13_observability/design.md:415](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/13_observability/design.md:415).

<a id="gap-066"></a>

### GAP-066: Keep beta-only exceptions from approving another release

**Type:** Release decision. **State:** Open.

**Design:** BETA1-BEDROCK and BETA1-FLOOR explicitly expire before the next release. Other beta evidence also records an unexplained S3 readiness timeout.

**Current V3:** Core floor evidence has changed. Bedrock service skips remain unproved. A historical passed/skipped profile does not certify present service durability or renew an exception.

**V2 approach:** V2 has no corresponding optional backend or beta exception. Its release state cannot resolve the current gates.

**Reconciliation:** Before a new release, decide scope and obtain exact-candidate evidence or a separately recorded exception. Do not restart parked Bedrock work during core document reconciliation.

**Evidence:** [docs/design/99_delivery/scope-ledger.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/99_delivery/scope-ledger.md); [docs/design/99_delivery/evidence.md:32](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/99_delivery/evidence.md:32); [lib/jido/persistence/bedrock.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence/bedrock.ex:1); [lib/jido/storage.ex:9](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/storage.ex#L9).


## Cross-topic documents

<a id="gap-067"></a>

### GAP-067: Separate approval status from implementation status

**Type:** Document correction. **State:** Open.

**Design:** docs/design/AGENTS.md permits Pending approval or Approved only. The index uses Current, Selected and implemented, Implemented, and similar values. Some topic headers say approved while the index says pending.

**Current V3:** Code demonstrates implementation only. The index is the declared approval source. Earlier implementation or a positive conversation response does not approve an entire design document.

**V2 approach:** The checked V2 library has no equivalent current design review-status workflow. There is no V2 approval rule to apply.

**Reconciliation:** Use the two allowed approval values and a separate implementation/evidence field. Do not infer any document approval. This report is added as Pending approval; existing rows are unchanged in this task.

**Evidence:** [docs/design/AGENTS.md:11](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/AGENTS.md:11); [docs/design/README.md:98](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/README.md:98); [docs/design/01_agent/alignment.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/01_agent/alignment.md).

<a id="gap-068"></a>

### GAP-068: Replace missing paths and obsolete line evidence

**Type:** Evidence update. **State:** Open.

**Design:** Evidence includes absent Builder source/tests, old Agent Codec subpaths, old Observe lifecycle tests, absent Bedrock integration tests, and pre-refactor Server line numbers.

**Current V3:** Current code is split into owner modules. A source path or an old Proven label alone does not show that the current requirement is tested.

**V2 approach:** Pinned V2 source can establish old behavior, but cannot serve as current V3 acceptance evidence. Historical links must identify the version/commit.

**Reconciliation:** Replace missing paths with current source/test links, or mark the evidence historical. Keep saved gate results tied to a commit. Use the link audit and requirement inventory below as review aids.

**Evidence:** [docs/design/01_agent/alignment.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/01_agent/alignment.md); [docs/design/02_agent-authoring/alignment.md](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/02_agent-authoring/alignment.md); [docs/design/07_persistence/alignment.md:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/07_persistence/alignment.md:1); [docs/design/99_delivery/alignment.md:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/99_delivery/alignment.md:1).

<a id="gap-069"></a>

### GAP-069: Apply the review authority and completion rules consistently

**Type:** Document correction. **State:** Open.

**Design:** VISION, briefings, designs, alignment matrices, and delivery records can state different supported APIs or completion labels. Some planning language still instructs a return to the older design.

**Current V3:** lib is canonical for present behavior. The user explicitly removed Builder and selected V2 as the fallback for unclear intent. A found document difference does not automatically authorize a source change.

**V2 approach:** V2 is a historical API reference. It does not replace explicit V3 decisions, prove distributed contracts, or approve an old V3 design.

**Reconciliation:** Resolve each numbered question, record the decision and owner, then update dependent documents. Implement selected code changes separately. Keep historical facts, current facts, proposed decisions, and approval separate.

**Evidence:** [docs/design/README.md:12](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/README.md:12); [docs/design/VISION.md:176](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/VISION.md:176); [docs/design/AGENTS.md:56](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/AGENTS.md:56).

## Contracts that mainly match the current implementation

These are the main matching contracts found in the owner source. This table is not a new requirement-by-requirement test certification. The numbered gaps identify exceptions and omissions. Broad callback purity and outside-owner requirements remain design obligations; source inspection cannot prevent arbitrary application I/O.

| Topic | Main matching contracts | Current source |
| --- | --- | --- |
| 00 | Immutable library values; host ownership; one live commit; no external-I/O rollback; ordinary Directives have no general replay guarantee. | [lib/jido/agent.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent.ex:1) |
| 01 | Definition/instance forms; identity/state coherence; combined state and write ownership; direct cmd; versioned default/custom checkpoint envelopes. | [lib/jido/agent/checkpoint.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/checkpoint.ex:1) |
| 02 | Canonical data construction; ordered declarations; inline Action compilation; trusted Codec decoding; pure extension lowering; constructor delegation. | [lib/jido/agent/dsl/compiler.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/dsl/compiler.ex:1) |
| 03 | Exact closed Ref; namespace/partition/ID validation; unchanged logical identity; local facade; identity separated from location and authority. | [lib/jido/agent/ref.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/ref.ex:1) |
| 04 | Preparation before selection; fixed source routing; complete candidate; Directive validation; serial owned reduction; direct/live finalization. | [lib/jido/agent/runner.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent/runner.ex:1) |
| 05 | Ordered declarations; unique state keys; isolated prepared/runtime inputs; owned Directives; runtime readiness; bounded persistence and topology contributions. | [lib/jido/plugin/normalizer.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/plugin/normalizer.ex:1) |
| 06 | Required checkpoint before live replacement; one state-version advance even for equal state; reply after commit; ordered fail-fast effects; retained commit after effects fail. | [lib/jido/agent_server/turn.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/turn.ex:1) |
| 07 | Binary storage; atomic conditional write; record/revision validation; create-only startup; tombstones; fail-closed decoding; write-result classification. | [lib/jido/persistence.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/persistence.ex:1) |
| 08 | One active Turn; OTP postponement; admission/overload/timeouts/cancellation; startup cleanup; ready publication; owned work termination; bounded definition upgrade. | [lib/jido/agent_server.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server.ex:1) |
| 09 | Standard OTP instance; configuration validation; five standard children; namespace binding; local Ref facade; ID/PID compatibility; persistence precedence. | [lib/jido.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido.ex:1) |
| 10 | one_for_one instance tree; peer Agent Servers; Plugin wrappers; coherent bootstrap; logical child tracking; exact known-node placement and no local fallback. | [lib/jido/agent_server/plugin_child.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/agent_server/plugin_child.ex:1) |
| 11 | Pure definitions/plans; contribution expansion; local activation/readiness/repair; additive updates; exact placement; lifecycle Signals; no cluster authority. | [lib/jido/topology/controller.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/topology/controller.ex:1) |
| 12 | Five Splode classes; six error types; callback reason preservation; bounded/redacted four-key projection; protocol results. Registry exceptions are in GAP-050/051. | [lib/jido/error.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/error.ex:1) |
| 13 | Semantic schema 1; privacy limits; bounded measurements; low-cardinality default tags; logger modes; optional API-only OpenTelemetry; task/W3C propagation. | [lib/jido/telemetry/semantic.ex:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/lib/jido/telemetry/semantic.ex:1) |
| 90 | Action/Signal lower-layer ownership; core local runtime; host service/client ownership; external cluster/transport/AI policy. | [mix.exs:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/mix.exs:1) |
| 99 | Historical release identity, scope, and exception records are explicit. They remain history and do not certify this candidate. | [docs/design/99_delivery/evidence.md:1](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/99_delivery/evidence.md:1) |

## Requirement inventory and limits

The inventory below lists every requirement declaration extracted from each owner `design.md`: **864 declarations**. It includes explicitly declared retired AGT-REQ-005/031/032/038, AUTH-REQ-010/026/027/029/031/032/059, PLG-REQ-017/069–076, and ERR-REQ-019. References and numeric ranges are not counted as declarations. TOP-REQ-002 and TURN-REQ-035 have no active declaration in these files; PLG numeric holes must not be filled by inference. PLG-REQ-061–076 were recovered from Git history during this review, with 069–076 explicitly retired under GAP-023.

The inventory records where each requirement is defined; it does not claim that every stated requirement has a passing test. Review the matching-contract table and exception list together. Delivery, conditional migration, external provider, and pure application-callback requirements need their own evidence before release.

| Topic | Declared count | Exact declared IDs | Main exceptions / review entries |
| --- | --- | --- | --- |
| [00_overview](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/00_overview/design.md) | 66 | `OVR-REQ-001`–`OVR-REQ-066` | GAP-001–004, 021, 029–031, 058, 067–069 |
| [01_agent](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/01_agent/design.md) | 48 | `AGT-REQ-001`–`AGT-REQ-048` | GAP-001–002, 005–008, 028, 050–051 |
| [02_agent-authoring](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/02_agent-authoring/design.md) | 64 | `AUTH-REQ-001`–`AUTH-REQ-064` | GAP-001, 009–014 |
| [03_agent-identity](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/03_agent-identity/design.md) | 28 | `ID-REQ-001`–`ID-REQ-028` | GAP-015–016, 031, 049 |
| [04_turn-evaluation](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/04_turn-evaluation/design.md) | 43 | `TURN-REQ-001`–`TURN-REQ-034`, `TURN-REQ-036`–`TURN-REQ-044` | GAP-003, 007, 017–018 |
| [05_plugins](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/05_plugins/design.md) | 73 | `PLG-REQ-001`, `PLG-REQ-003`, `PLG-REQ-005`, `PLG-REQ-007`, `PLG-REQ-009`, `PLG-REQ-011`–`PLG-REQ-029`, `PLG-REQ-031`–`PLG-REQ-032`, `PLG-REQ-035`–`PLG-REQ-040`, `PLG-REQ-042`–`PLG-REQ-044`, `PLG-REQ-046`, `PLG-REQ-049`–`PLG-REQ-051`, `PLG-REQ-053`–`PLG-REQ-056`, `PLG-REQ-059`–`PLG-REQ-088` | GAP-002, 018–025 |
| [06_commit-and-effects](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/06_commit-and-effects/design.md) | 44 | `COMMIT-REQ-001`–`COMMIT-REQ-044` | GAP-021, 026–028 |
| [07_persistence](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/07_persistence/design.md) | 51 | `PERS-REQ-001`–`PERS-REQ-051` | GAP-008, 020, 028–036 |
| [08_agent-server](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/08_agent-server/design.md) | 77 | `SRV-REQ-001`–`SRV-REQ-077` | GAP-021, 037–042, 050, 053 |
| [09_jido-instance](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/09_jido-instance/design.md) | 56 | `INST-REQ-001`–`INST-REQ-056` | GAP-030–031, 043, 053 |
| [10_runtime-topology](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/10_runtime-topology/design.md) | 51 | `RT-REQ-001`–`RT-REQ-051` | GAP-040, 044, 053 |
| [11_topology-control-plane](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/11_topology-control-plane/design.md) | 100 | `TOP-REQ-001`, `TOP-REQ-003`–`TOP-REQ-101` | GAP-001, 018, 033, 045–049 |
| [12_errors-and-contracts](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/12_errors-and-contracts/design.md) | 24 | `ERR-REQ-001`–`ERR-REQ-024` | GAP-002, 008, 032–035, 042, 050–053 |
| [13_observability](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/13_observability/design.md) | 58 | `OBS-REQ-001`–`OBS-REQ-058` | GAP-021, 050, 054–058 |
| [90_package-boundaries](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/90_package-boundaries/design.md) | 39 | `PKG-REQ-001`–`PKG-REQ-039` | GAP-001, 031, 058–060, 062 |
| [99_delivery](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/99_delivery/design.md) | 42 | `DEL-REQ-001`–`DEL-REQ-007`, `DEL-REQ-009`–`DEL-REQ-043` | GAP-036, 049, 058, 061–066 |

### Outside the active core queue

- TOP-REQ-006–058 and TOP-REQ-061 describe external distributed providers/policy. No current core implementation is claimed.
- ID-REQ-021/022 include Ref-addressed external delivery/placement. Current known-node local primitives do not prove a general transport or placement service.
- PKG-REQ-006/033 require evidence in other integration repositories; PKG-REQ-031/032/039 describe external/future contracts. This review makes no AI/Browser/transport package claim.
- PERS-REQ-021 is a future public-control migration, not a currently implemented code set.
- AGT-REQ-005/031/032/038, AUTH-REQ-010/026/027/029/031/032/059, PLG-REQ-017, and ERR-REQ-019 are retired. TOP-REQ-002 is retired by owner prose. Numeric holes do not establish missing implementation work.
- Real Bedrock profiles remain paused/unproved. Record their release effect; do not resume parked upstream work from this analysis.

## V2 research summary

| Concern | V2 solution | Limit for V3 reconciliation | Primary source |
| --- | --- | --- | --- |
| Agent mutation | Deep merge; validation separate. | Restore merge under the user rule; retain V3 immediate validation and write ownership under the explicit GAP-006 decisions. | [lib/jido/agent/state.ex:19](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent/state.ex#L19) |
| Live values | Schema validation, no general portability gate. | Do not copy Server-private injection into V3 Agent values. | [lib/jido/agent/state.ex:37](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent/state.ex#L37) |
| Durable values | Version-1 checkpoint maps; term storage/encoding. | No general checkpoint portability check; retain V3 durable rejection under GAP-008. | [lib/jido/persist.ex:388](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/persist.ex#L388) |
| Cron durability | Persisted schedule manifest and a message durability check. | No current pending occurrence/acknowledgement guarantee. | [lib/jido/scheduler.ex:67](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/scheduler.ex#L67) |
| Plugin declaration | One Plugin module with metadata and broad callbacks. | Same module shape, different V3 callback authority and timing. | [lib/jido/plugin.ex:220](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/plugin.ex#L220) |
| Plugin persistence | Keep/drop/externalize owned state; on_restore rehydration. | Current dump/load and custom opaque Agent payloads differ. | [lib/jido/plugin.ex:469](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/plugin.ex#L469) |
| Routing | Server built strategy/Agent/Plugin routes; Signal hooks could transform/override. | Current immutable source and shared direct/live Turn are V3 contracts. | [lib/jido/agent_server/signal_router.ex:10](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server/signal_router.ex#L10) |
| Effects | GenServer Directive queue and drain loop. | No current commit/after_commit/Outcome settlement contract. | [lib/jido/agent_server.ex:13](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/agent_server.ex#L13) |
| Checkpoint identity | Module and ID key. | No stable namespace Ref, token CAS, tombstones, or current cross-module migration contract. | [lib/jido/persist.ex:629](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/persist.ex#L629) |
| Storage | ETS/File/Redis checkpoints and Thread journals. | Expected journal revision is not atomic Agent checkpoint CAS. | [lib/jido/storage.ex:43](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/storage.ex#L43) |
| Local instance | Four base children plus optional worker pools. | Current Spawn Registry and five-child lifecycle are V3 additions. | [lib/jido.ex:370](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido.ex#L370) |
| Topology | Pod is an Agent with persisted __pod__ topology/version and mutation/reconcile helpers. | No current separate Topology Controller target record, Codec, or cluster fence. | [lib/jido/pod.ex:5](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/pod.ex#L5) |
| Sensor input | Sensor behaviour/runtime and Plugin subscriptions. | Current standard OTP child + SensorManager replaces it. | [lib/jido/sensor.ex:37](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/sensor.ex#L37) |
| Errors | Splode classes/types, raw controls, bounded transport helper. | No current stable-code registry contract. | [lib/jido/error.ex:37](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/error.ex#L37) |
| Observation | Observe facade, tracer callbacks, telemetry and causal context. | Current closed semantic catalog/API bridge is a V3 replacement. | [lib/jido/observe.ex:8](https://github.com/agentjido/jido/blob/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2/lib/jido/observe.ex#L8) |

Module-absence checks used the complete V2.3.3 `lib/` tree plus symbol searches. There is no V2 Agent/Topology Builder, Agent Ref, authoring Codec/Registry, V3 Persistence.Store, V3 Turn/Outcome, or required after_commit callback in that baseline. The tree contains V2 Pod, Sensor, Strategy, WorkerPool/InstanceManager, Memory, Thread, Identity, and Observe. Absence of a current module name is not proof that V2 solved the same problem; the functional counterparts above state the actual method and limits.

## Verification and evidence limits

- The repository was clean on release/v3 at the start. HEAD remained `35c9644addfcf20c89f5d2bcaa3c2af045b45859`. No lib, test, dependency, or historical Git change was made.
- Source and declared requirements were reviewed across all 16 topics. The prior detailed review supplied broad current-owner source inspection. This pass added V2 primary-source research, current reverse inventory, exact requirement extraction, protocol/callback checks, and fresh error probes.
- Fresh probes on Elixir 1.18.5 / OTP 27.3.4.12 confirmed three missing code lookups and an ordinary Ref validation error with no registered code.
- The previous review ran 95 focused tests with zero failures. Those are previous results, not a new test run in this task.
- The prior release sync saved 2,342 tests, zero failures, two existing skips, and 93.5% coverage, plus passing CI/floor results. Those are historical exact-source evidence; this analysis did not rerun the full suite, services, package build, or CI.
- Evidence links identify source paths/lines and the pinned V2 commit. Automated checks validate entry IDs, requirement counts, local link existence/line bounds, V2 link targets, and the final Git diff. They do not prove every runtime path or external service.
- The initial analysis added this report and its Pending approval index row. The subsequent voice review records selected decisions in the corresponding entries and updates the affected topic documents. GAP-006, GAP-007, and GAP-008 are recorded in the Agent design and alignment. GAP-009, GAP-010, and GAP-012 are recorded in the authoring documents; GAP-011/013 are corrected in the owner design, and GAP-014 evidence paths are corrected. GAP-015/016 are recorded in the identity design and alignment. GAP-018 and GAP-021 are recorded in Plugin documents, with GAP-019/020 corrections. GAP-026/038/039 are corrected in the commit and Server documents under the selected hook contract. GAP-022 is corrected in the Plugin design and delivery ledger; GAP-023 records required Scheduler durable-delivery removal, which remains a code change to complete. Other gaps remain as stated; complete document approval has not been inferred.

## Suggested discussion order

Continue with the after-commit hook in GAP-021. GAP-018 one-module authoring is settled; GAP-019/020 owner corrections are recorded. GAP-015 is corrected in identity documents; GAP-016 partition compatibility is settled. GAP-017 is an evaluator evidence refresh with no new API decision. GAP-012 plain-map route defaults are settled. GAP-009 block authoring and GAP-010 route helpers are settled. GAP-011/013 are corrected in the owner design. GAP-014 evidence paths are corrected; Builder cleanup remains under GAP-001. Builder removal in GAP-001, validation/write ownership in GAP-006, schema policy in GAP-007, and durable portability in GAP-008 are settled. GAP-005 is selected but still needs implementation. Resolve Plugin declaration and hook contracts GAP-018–025 before commit/Server questions. Resolve persistence format, identity, and adapter questions GAP-029–035 before dependent instance and Topology records. Then complete errors, telemetry, and delivery/index updates.

For each resolved entry, record the selected contract, affected requirement IDs, affected documents/code, migration effect, and acceptance evidence. Keep the GAP number stable after resolution. The review order does not authorize implementation, publication, or restoration of every V2 feature.
