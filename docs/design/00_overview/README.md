> Approved seam review entry point. Detailed owner-seam contracts and
> implementation evidence remain open.

# 00 — Core model, shared terms, and invariants

## Briefing

The recommended V3 architecture keeps the implemented local runtime as its
base. It keeps immutable Agent values, direct evaluation, one Agent Server
commit point, Builder, Codec, owned children, public PID APIs, persistence
adapters, static local Topology, and current observation paths. The main target
changes are source-Signal route selection, isolated Plugin inputs, stable Agent
identity, definition revision, stronger durable lifecycle rules, and coherent
Plugin runtime replacement. This seam defines only the shared model and
invariants. Each owner seam defines its detailed API.

The [design review index](../README.md#document-review-status) is the source of
truth for document approval. The Overview documents and 12 decisions were
approved on 2026-09-09. The exact Plugin ownership model remains deferred
owner-seam design work. Approval does not mean that target behavior is present
in the code.

## Why this seam exists

- Owner: the shared Jido Agent model and cross-system boundaries.
- Owns: common terms, the Agent-to-Turn-to-commit model, the Jido and OTP
  boundary, cross-system invariants, owner-seam assignments, and dependency
  gates.
- Does not own: detailed structs, callback signatures, error codes, storage
  operations, supervision layouts, or topology update protocols.

## Current and target state

| Area | Canonical current state | Recommended target |
| --- | --- | --- |
| Turn selection | Plugins can change a Signal before routing. Jido requires exactly one route match. | Preserve the source Signal. Select the first Router match before Plugin preparation. Fix that executable for the Turn. |
| Evaluation | Direct and live commands share the private Runner. | Keep one candidate-evaluation boundary. Only the live Agent Server commits. |
| State ownership | An executable writes domain state. Each stateful Plugin can replace one owned state entry. Plugins can read the complete Agent during preparation. | Keep separate write owners. Give each Plugin only its declared Agent view, owned input, and owned Directives. |
| Commit and effects | One successful live Turn increments `state_version` once. Directive work starts after commit. Action and Flow I/O can occur before commit. | Keep one commit point. Do not claim rollback for pre-commit external I/O. |
| Identity and restore | Agent Ref and definition revision are implemented. A namespaced instance resolves the current local PID through an additive Ref facade. | Keep current ID and PID APIs. Keep identity separate from location and authority. |
| Durability | Version-2 compatible records and version-3 stable Ref records use exact-byte CAS. Persistent startup writes revision zero before `:ready` publication and start success. Every required write failure stops the activation. | Keep the explicit legacy collision, no-automatic-rewrite, and downgrade limits. |
| Runtime recovery | A named instance restores the last nondurable runtime checkpoint after an abnormal nonpersistent Server restart. Each Plugin generation gets matching committed state and state version at start. | Keep runtime-checkpoint restore and coherent Plugin bootstrap. |
| Topology and observation | Static local Topology, manual repair, semantic telemetry, legacy telemetry, tracing, and debug paths exist. | Keep static local Topology and supported observation APIs. Defer live topology control and any removal until owner seams define migration and proof. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Route and Plugin input contract | Current preparation can change selection and expose the complete Agent. | One fixed executable from the source Signal and isolated Plugin-owned inputs. | 01 Agent, 04 Turn evaluation, 05 Plugins |
| Stable identity and definition revision | Ref value, instance namespace, Ref facade, stable key, and restore checks are implemented. Runtime Topology still uses compatible local handles. | Preserve exact Ref identity when topology work adds new target forms. | 10 |
| Durable lifecycle | Current creation, write-error, and delete rules do not give one safe record lifecycle. | Initial active records, loss of write authority, and tombstone semantics. | 06 Commit and effects, 07 Persistence, 08 Agent Server, 10 Runtime topology |
| Plugin ownership and replacement | Four closed owner facets, coherent runtime replacement, Persistence conversion, and Topology planning integration are implemented. | Keep compatibility proof through delivery. | 05, 08, 09, 10, 11 |
| Public values and errors | The supported structs, maps, tuples, atoms, PIDs, OTP values, and exceptions have an owner and compatibility rule. | Preserve the revalidated inventory through delivery. | 12 Errors and contracts, 90 Package boundaries, value owners |
| Acceptance coverage | Skipped research tests specify several target contracts but do not prove them. | Passing owner-seam evidence for each approved Overview requirement. | All dependent seams, closed by 99 Delivery |

## Approved direction

The user approved these shared decisions on 2026-09-09. Items 4 and 5 approve
the direction but leave the listed owner-seam details open.

1. **Route contract:** Select the first Router match from the source Signal
   before Plugin preparation. Admission and preparation cannot replace it.
   Make that fixed selection available to the observation boundary for safe
   logging.
2. **Nonpersistent restart:** Keep the current last-commit runtime checkpoint
   rule for abnormal restart in the same Jido instance.
3. **Stable identity:** Make Agent Ref a V3 target and keep current ID and PID
   APIs during migration.
4. **Definition revision:** Keep `vsn` as the canonical field name. Store it
   on the immutable Agent definition and copy it to each instance. A generated
   module owns it at compile time and defaults it to `1`. A checkpoint and
   durable record store a snapshot for restore validation. Agent Ref and
   runtime `state_version` do not contain it.
5. **Plugin ownership:** Separate Agent, Agent Server, Persistence, and
   Topology responsibilities as the target direction. Defer the exact facet,
   callback, and composition model until seam 05 receives more design work.
6. **Custom checkpoints:** Keep complete Agent `checkpoint/2` and `restore/2`
   callbacks until their composition with Persistence facets is explicit.
7. **Durability scope:** Require initial active records, loss of write authority
   after every write error, and tombstones for V3.
8. **Compatibility APIs:** Keep DSL and direct authoring, Builder, Codec,
   neutral definitions, custom routing, owned children, public PID APIs, and
   local debug paths for the V3 release.
9. **Topology scope:** Keep static local activation and repair. Defer owner-Agent
   live control and live target updates.
10. **Package boundary:** Keep Jido core local. Keep general durable, cluster,
    and transport services outside core.
11. **Public values:** Approve value roles only. Let seam 12, seam 90, and each
    value owner decide exact shapes and migration.
12. **Observation:** Make semantic Agent events the single V3 source. Remove
    legacy Agent Server telemetry and `Jido.Observe`. Keep the OpenTelemetry API
    mapping optional, and keep W3C tracing and bounded debug history.

## Dependencies

- Prerequisites: None. This is the first alignment gate.
- Dependents: 90, 12, 01 through 11, 13, and 99, in the order in
  `docs/design/AGENTS.md`.
- Blockers: The shared direction is approved. Plugin ownership composition is
  deferred. Detailed owner-seam contracts and acceptance evidence remain.
- Lower layers: `jido_action` owns executable work. `jido_signal` owns the
  Signal envelope and ordered route matching. Jido owns how these contracts
  become one Agent Turn.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
