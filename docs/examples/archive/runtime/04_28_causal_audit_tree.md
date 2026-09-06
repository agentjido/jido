> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Causal Audit Tree and Analysis Graph

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_28_causal_audit_tree`
- **Status:** doesn't work yet
- **Complexity level:** 5 - System
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Record an immutable proof of asserted event causation and build separate analysis views without inferring cause from event order.
- **User story:** As an auditor, I verify why each event exists, where it ran, which events contributed to an aggregate, and whether the record changed.
- **Trigger or input:** One coordinator Signal, child delegation and result Signals, mocked tool outcomes, lifecycle events, and Directive outcomes.
- **Agent state:** The Actor keeps only its domain result and audit references. Each audit event has event ID, trace ID, direct cause ID, Agent ID, execution scope ID, type, and deterministic logical time. Semantic memory is a separate mutable projection.
- **Actions or Flow:** One coordinator Flow delegates to two local research Actors. Each child performs one mocked tool effect and returns a complete local trace. The parent grafts each trace at its invocation event and aggregates both results. Actions and Flows can perform external effects; the audit captures these effects without converting them into Directives.
- **External interactions:** An append-only audit journal, hash function, trace exporter, and mocked research tools. A distributed extension uses a hybrid logical clock and does not use wall-clock order as proof of causation.
- **Runtime Directives or capabilities:** Child start, Signal delivery, and stop are runtime commands. The record also captures complete Directive dispatch outcomes. Directives are not the exclusive effect boundary.
- **Expected result:** The committed proof view is one rooted causal tree. Each non-root event has exactly one asserted direct cause. Execution scope containment is a separate relation. Fan-out and aggregation keep one direct cause per proof-tree event and use separate `contributes_to` edges in a derived analysis DAG. A Merkle root changes when any recorded event changes.
- **Failure cases:** A killed child leaves an incomplete but structurally valid trace prefix. Reject a missing cause, more than one direct cause, causal cycle, non-increasing logical time on a causal path, invalid graft root, cross-trace ID collision, missing lifecycle outcome, or hash mismatch.
- **Jido features under pressure:** Explicit causal propagation, distinct scope containment, Action and Flow effect capture, complete lifecycle and Directive outcome capture, durable append-only journaling, deterministic logical clocks, child trace grafting, Merkle commitment, trace export, and projection rebuild.
- **Source framework and links:** [Volodymyr Pavlyshyn: A Tree You Can Prove, a Graph You Can Think In](https://volodymyrpavlyshyn.substack.com/p/a-tree-you-can-prove-a-graph-you), [Simon Foldvik: Causal-Temporal Event Graphs](https://arxiv.org/abs/2604.17557), and [originating Codex task](codex://threads/01a06741-9c58-7a83-ae90-c80caef67fa6)

## Deterministic test scenario

1. Send one Signal to a coordinator and delegate to two local research Actors.
2. Make each child perform one mocked tool call and report one result.
3. Make the coordinator aggregate both results one time.
4. Assert the causal tree, separate execution-scope containment, separate
   contribution edges, and one final aggregate.
5. Kill one child in a second run and prove that the recorded prefix stays a
   valid rooted tree.
6. Change one stored event and prove that the Merkle root changes.
7. Rebuild a small mutable semantic-memory projection without changing the
   immutable audit tree or its Merkle root.

## Smallest missing contracts

1. A public causal event envelope and explicit cause-propagation context.
2. A separate execution-scope envelope and containment relation.
3. Hooks for Action, Flow, child lifecycle, tool effect, and Directive outcome
   events.
4. A durable append-only journal with stable event order and trace export.
5. An injectable deterministic logical clock, plus a hybrid logical clock for
   distributed runs.
6. A validated local-trace graft operation and Merkle commitment format.

These contracts must not infer causation from timestamps, mailbox order, span
nesting, or execution-scope containment.

## Spike result

The local spike passes with explicit application-owned event envelopes,
logical time, direct cause IDs, scope relations, contribution edges, journal
deduplication, a proof validator, a Merkle commitment, and a rebuildable
semantic projection. A failed research operation leaves a valid journal
prefix.

The complete profile doesn't work yet. Jido does not automatically capture
Action, Flow, child lifecycle, tool, and Directive outcome events. The spike
also uses local research calls instead of supervised child Actors. The code
shows the data contract that runtime instrumentation must preserve without
adding that instrumentation to core Jido.

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/runtime/04_28_causal_audit_tree/causal_audit_tree.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_28_causal_audit_tree/causal_audit_tree_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: SDK contract.
- Remaining work: Manual proof data works. Automatic Action, Flow, child, effect, and Directive outcome capture is missing; the spike does not start child Actors.

An example-scope gap is not evidence of a core Jido defect.
