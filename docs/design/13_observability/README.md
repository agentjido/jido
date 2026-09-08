# 13 — Observability

Status: Pending approval.

## Briefing

This seam defines the public observation contract for the Jido V3 runtime. It
keeps semantic Telemetry events as the source contract. It defines bounded
event data, correlation, logs, metrics, failure isolation, and an optional
OpenTelemetry translation boundary. It does not give an observer execution
authority, make telemetry durable, or put an exporter in the SDK.

The current runtime emits semantic events for Agent activation and stop, Turn
evaluation and live result, commit, Directive work, and terminal Turn
settlement. It also emits older Agent Server events and supports
`Jido.Observe`, process-local tracing, configurable logging, and debug history.
These older paths stay available during a staged migration.

## Why this seam exists

- Owns: Jido semantic event names and meanings, measurements, safe metadata,
  runtime correlation, default metrics, semantic log policy, observer failure
  rules, compatibility, and the optional Jido-to-OpenTelemetry mapping.
- Coordinates: Agent Ref identity, Signal trace carriers, Turn and commit
  boundaries, persistence results, Agent Server Outcomes, local Topology, and
  optional control-plane events.
- Does not own: Agent behavior, persistence policy, cluster authority,
  exporter processes, collectors, storage backends, dashboards, alert rules,
  vendor credentials, or AI-provider observation.

The contract must let an operator answer four separate questions: what became
live, what settled later, what failed, and how related work is correlated. A
handler must not be able to change any of those results.

## Current and target state

| Area | Current state | Target state |
| --- | --- | --- |
| Semantic Agent events | Lifecycle `activate` and `stop`, Turn, commit, Directive, and `turn.settled` events exist. | Keep these meanings and add approved lifecycle operations only at real boundaries. |
| Missing runtime visibility | Admission rejection, persistence operations, and local Topology operations have no semantic event families. | Add bounded events at the owner boundaries. Do not infer events from logs or debug history. |
| Identity and correlation | Events use Agent ID, module, activation ID, Jido instance, partition, Turn and Signal IDs, and legacy/W3C-derived trace IDs. | Project the approved Agent Ref namespace, partition, and ID. Keep activation, Turn, Signal, trace, parent, and causation as separate fields. |
| Outcome timing | A successful Turn span stops when the commit becomes live. `turn.settled` occurs after Directive work. | Preserve this split in Telemetry, logs, metrics, and OpenTelemetry. |
| Safety | Semantic metadata uses an allowlist and semantic emission catches handler faults. Older observation paths can accept broader data. | Apply one bounded projection to all new semantic families. Keep payloads, state, raw errors, records, and handles out. |
| Metrics and logs | Default metrics and the built-in log consumer use older Agent Server events. | Add semantic metrics and logs before any old path is deprecated. Keep identity out of default metric tags. |
| OpenTelemetry | Jido has no OpenTelemetry dependency or bridge. | Add an optional translation layer only if approved. The host owns the SDK, sampling, exporters, collector, and credentials. |

All target changes in this seam are pending approval. The current code is the
canonical implementation record.

## Major gaps and work remaining

| Gap | Required outcome |
| --- | --- |
| Incomplete catalog | Add admission-rejection, persistence-operation, and local Topology-operation evidence with exact schemas and tests. |
| Transitional identity | Add the Agent Ref projection after seam 03 is approved. Keep current fields for a documented overlap period. |
| Split consumers | Move default metrics and logs to semantic events and prove equal or better operational coverage. |
| Incomplete propagation | Define explicit trace transfer across each Jido-owned Task boundary and keep Signal W3C propagation under `jido_signal` ownership. |
| No OpenTelemetry bridge | Decide package ownership, span timing, optional dependency policy, and compile matrix before implementation. |
| Compatibility debt | Inventory users of legacy Agent Server events, `Jido.Observe`, tracing, logs, and debug history before any deprecation. |
| External link drift | The main design review table and seam 99 still name removed seam files. Separate owner-scoped edits must point them to these three files. |

## Decisions requested

1. Approve the event catalog in [design.md](design.md), including target
   admission, persistence, and local Topology families.
2. Approve `agent_namespace`, `agent_partition`, and `agent_id` as the semantic
   projection of the Agent Ref. Keep `jido_instance` and `partition` during the
   compatibility interval.
3. Approve lifecycle operations `activate`, `stop`, `hibernate`, and `thaw`.
   Represent record creation and deletion as persistence operations.
4. Approve the status and stage vocabularies. Do not expose private evaluator
   or Plugin callback stages.
5. Approve semantic log modes `off`, `errors`, `interesting`, and `all`, with
   safe fields only.
6. Approve an optional `Jido.OpenTelemetry` bridge in core. Keep the SDK,
   exporter, collector, sampling policy, and credentials in the host.
7. Decide whether the OpenTelemetry Turn span ends at the live result or at
   settlement. In both cases, it must report result and settlement as separate
   facts.
8. Approve additive schema evolution and a measured overlap period before any
   legacy observation API is removed.

## Dependencies

- [Core model](../00_overview/alignment.md) defines the result, settlement,
  privacy, and compatibility invariants.
- [Package boundaries](../90_package-boundaries/alignment.md) assign semantic
  Agent observation to Jido and exporter infrastructure to the host.
- [Errors and contracts](../12_errors-and-contracts/alignment.md) owns safe
  public error projections.
- [Agent](../01_agent/alignment.md), [Turn](../04_turn-evaluation/alignment.md),
  [Plugins](../05_plugins/alignment.md), and
  [commit and effects](../06_commit-and-effects/alignment.md) define the
  evaluation and live-result boundaries.
- [Agent identity](../03_agent-identity/alignment.md) owns Agent Ref fields.
- [Persistence](../07_persistence/alignment.md),
  [Agent Server](../08_agent-server/alignment.md),
  [Jido instance](../09_jido-instance/alignment.md), and
  [runtime topology](../10_runtime-topology/alignment.md) own the runtime facts
  that observation reports.
- [Topology control plane](../11_topology-control-plane/alignment.md) owns
  optional distributed events and authority meaning.

## Documents

- [Design](design.md) — target event, data, consumer, bridge, compatibility,
  and evidence requirements.
- [Alignment](alignment.md) — current evidence, gaps, old-claim dispositions,
  acceptance gates, migration notes, assumptions, and blockers.
