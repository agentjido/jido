# Stable Agent identity gap analysis

> Analysis report. The stable Agent identity design is a deferred proposal. This
> report describes current implemented behavior and does not approve or define a
> new public API.

## Scope and owner

This report covers only the stable Agent identity seam. It checks identity across
Agent values, Jido instances, Registry entries, persistence records, process
restarts, partitions, and explicit remote-node placement. It also checks the
identity data used by Agent-to-Agent Directives. Runtime code in `lib/` is the
source of truth for implemented behavior.

Jido core owns the current Agent value, Agent Server lifecycle, Jido instance
Registry, and persistence record key. The proposed `Jido.Agent.Ref` is therefore
a Jido core contract. `jido_signal` owns general Signal dispatch and transport.
The owner of a future cluster directory and the owner of durable activation
authority are not decided in this seam.

## Implemented baseline

The following items are current facts.

1. A `%Jido.Agent{}` instance has one identity field, `id`. The value must be a
   nonempty string. The Agent value does not contain its Jido instance or its
   partition. See `lib/jido/agent.ex:96-123` and
   `lib/jido/agent.ex:327-333`.
2. A live registered Agent is unique in one local Jido instance and one
   partition. Each Jido instance starts its own unique-key Registry. The
   Registry key is `{:agent, Jido.partition_key(id, partition)}`. See
   `lib/jido.ex:347-370`, `lib/jido.ex:449-453`, and
   `lib/jido/agent_server.ex:295-310`.
3. The Jido instance identity is an atom, normally the instance module. `use
   Jido` has no `:namespace` option or namespace callback. See
   `lib/jido.ex:70-107` and `lib/jido.ex:144-165`.
4. A partition can be any term. The public type is `term()`, Agent Server option
   validation does not restrict the value, and `partition_key/2` accepts every
   non-nil term. See `lib/jido.ex:233-234`, `lib/jido.ex:417-425`, and
   `lib/jido/agent_server/options.ex:11-20`.
5. A persistence key uses `{instance, agent_module, partition, agent_id}`. The
   record repeats all four fields and validates all four on load. See
   `lib/jido/persistence.ex:119-131`, `lib/jido/persistence.ex:153-160`,
   `lib/jido/persistence.ex:284-307`, and
   `lib/jido/persistence.ex:330-363`.
6. The default checkpoint contains `agent_module`, `id`, the Agent definition,
   and state. Restore requires the requested module and restored ID to match.
   See `lib/jido/agent.ex:370-423`, `lib/jido/agent.ex:521-543`, and
   `lib/jido/persistence.ex:368-379`.
7. Persistent Agent Servers use compare-and-swap with an expected numeric
   revision. A later activation on another node can restore the same storage
   record. A stale Server then loses a conflicting write. This is write
   conflict detection, not exclusive live ownership. Deletion or expiry removes
   the revision history. See `lib/jido/persistence.ex:59-74`,
   `lib/jido/persistence.ex:248-281`, and
   `lib/jido/agent_server.ex:2887-2929`.
8. A nonpersistent Agent can keep its last local commit across an Agent Server
   process restart through `Jido.RuntimeStore`. This state is scoped to one Jido
   instance and is lost when that instance stops. See
   `lib/jido/agent_server/runtime_checkpoint.ex:8-50` and
   `lib/jido/runtime_store.ex:3-23`.
9. Local lookup resolves a current Registry PID for each explicit lookup and
   rejects a dead PID. It does not search other nodes. See
   `lib/jido.ex:530-554`, `lib/jido/agent_server.ex:295-304`, and
   `test/jido/agent_server/startup_test.exs:96-117`.
10. Explicit remote child placement sends the start operation to a selected
    Erlang node. The target node must run the same named Jido instance. The
    parent-child records keep remote PIDs, IDs, partitions, and a private spawn
    request identity. See `lib/jido/agent/directive.ex:164-190`,
    `lib/jido/agent_server/directive_runtime.ex:244-299`, and
    `lib/jido/agent_server/child_placement.ex:8-39`.
11. Agent-to-Agent parent and child Signal Directives use the PID stored in the
    live relationship. They do not resolve a canonical Agent Ref for each
    delivery. See `lib/jido/agent_server/directive_runtime.ex:120-167` and
    `lib/jido/agent_server/parent_ref.ex:4-25`.
12. Core does not implement `Jido.Agent.Ref`. The research example states that
    its application-level reference is a substitute for the missing core type.
    See `examples/99_research/99_11_stable_reference/stable_reference.ex:25-46`.

## Aligned contracts

These current contracts align in part with the seam proposal.

- Agent IDs are stable nonempty strings. A new Agent Server process can keep the
  same Agent ID after a supervised restart or a persistent restore.
- The live PID is separate from the immutable Agent value. Local lookup can
  return a replacement PID for the same ID after restart.
- The local Registry and persistence both separate equal IDs by Jido instance
  scope and partition, although they use different complete key shapes.
- The default checkpoint contains the Agent module and Agent ID. It rejects a
  checkpoint that restores another module or ID.
- Persistence records are portable terms. Process-local handles are rejected.
  Tests cover nested portable data and reject PIDs in checkpoints. See
  `test/jido/persistence/checkpoint_portability_test.exs:15-49`.
- Compare-and-swap prevents a stale activation from overwriting a newer stored
  revision. The cross-node research test verifies restore and stale-write
  conflict. See
  `test/jido/agent_server/distributed_authority_test.exs:10-30`.
- Explicit remote placement does not change the child Agent ID or partition.
  The target performs a local Registry lookup, while the origin Registry does
  not contain that child. See
  `test/jido/agent_server/distributed_child_test.exs:41-76`.
- Remote spawn request generations prevent an old or changed request from being
  accepted as the current child creation. This is activation-local request
  identity. It is not stable Agent identity. See
  `lib/jido/agent_server/spawn_registry.ex:29-64`.

## Gaps

### Missing implementation

MI-1. There is no canonical `Jido.Agent.Ref` struct, schema, constructor,
validator, equality contract, or serialization contract.

MI-2. A Jido instance has no stable string namespace. Runtime and persistence
use the Jido instance atom or module. There is no supported binding from a
stable namespace to a renamed or replaced instance module.

MI-3. Public instance functions accept an Agent ID plus optional partition, or a
PID. They do not accept one Ref-first target. Start functions return a PID, not
an Agent Ref. See `lib/jido.ex:144-185` and `lib/jido.ex:431-554`.

MI-4. Registry, persistence, relationships, Plugin contexts, and remote spawn
paths do not use one shared identity value. They copy `jido`, `partition`,
`agent_id`, and sometimes `agent_module` into separate fields. For examples,
see `lib/jido/agent_server/state.ex:4-15`, `lib/jido/plugin/init.ex:4-19`, and
`lib/jido/plugin/directive_context.ex:10-32`.

MI-5. Agent-to-Agent Signal Directives do not carry an Agent Ref. Parent and
child sends use a retained PID. Explicit remote placement selects a node and
builds a new child from an Agent module or Agent value; it does not place an
existing stable Ref.

MI-6. There is no cluster directory, Ref-to-location resolver, location version,
or stale-location protocol. The only general lookup is the local Registry.

MI-7. There is no cluster-exclusive activation claim, lease, or fencing token.
Numeric record revisions detect a stale write only after two live activations
can exist. The test for at most one live cluster owner is skipped. See
`test/jido/agent_server/distributed_authority_test.exs:32-39`.

MI-8. The default checkpoint has no explicit definition revision. It embeds a
definition and module, but it cannot identify one stable module-owned definition
revision as required by the larger deferred persistence design.

### Design/code conflict

DC-1. The proposed identity is `{namespace, partition, id}` with string
constraints. Current local identity is effectively `{jido_instance,
partition, id}`, where the instance is an atom and partition is any term.

DC-2. The proposal says that the Agent module is not part of process or durable
storage identity. Current persistence makes `agent_module` part of the storage
key and requires callers to supply it for load, delete, and thaw.

DC-3. The proposal says that Registry, persistence, Directives, placement, and
future transport use the same Ref. Current code uses different shapes for each
boundary.

DC-4. The proposal says dispatch resolves current runtime location from the Ref
for each delivery. Current `EmitToParent` and `EmitToChild` dispatch directly to
stored PIDs. Normal generated Agent commands also accept local or remote PIDs.

DC-5. The proposal separates stable identity from node location. Current remote
spawn creation includes an explicit target node and a parent PID in its private
request identity. These fields are valid for activation and request control, but
there is no separate stable Ref at that boundary.

DC-6. The deferred instance design shows `use Jido, namespace: "..."` and a
Ref-first facade. The implemented `use Jido` macro accepts only `:otp_app` and
`:persistence`, and its facade is ID/PID-first. See
`docs/design/09_jido-instance/jido-instance.md:181-211` and
`lib/jido.ex:70-107`.

### Missing decision

MD-1. Decide if stable namespace identity is required for the V3 core release,
or if the current instance-module identity is the released contract.

MD-2. Decide namespace syntax, normalization, uniqueness scope, and configuration
rules. Also decide how a namespace binds to one Jido instance on each node.

MD-3. Decide if partitions must be nil or nonempty strings. Current APIs and
tests use atoms such as `:blue`, so a string-only rule is a breaking change. See
`test/jido/instance_test.exs:145-171` and
`test/jido/instance_test.exs:206-216`.

MD-4. Decide the migration rule for persistence keys that include a Jido module
and Agent module. This includes lookup fallback, record rewrite, collisions, and
rollback behavior.

MD-5. Decide if one Ref can move between nodes while the same Ref remains live
on the old node. If it cannot, define the activation-transfer rule. If it can,
define read and write semantics during overlap.

MD-6. Decide which public operations are local-only and which operations can use
transport. Also decide if direct PID commands remain a supported low-level API.

MD-7. Decide the stale-location contract. This includes cache lifetime,
location generation, retry rules, and the result for a partitioned node.

MD-8. Decide package ownership for cluster location and durable activation
authority. The identity type belongs in Jido core, but general Signal transport
belongs in `jido_signal`. The authority service can require an application
storage provider or a higher orchestration layer.

MD-9. Decide if numeric compare-and-swap revisions are sufficient for the V3
durability statement. If exclusive activation is required, define a claim,
lease, or fencing token that remains safe across record deletion and expiry.

### Missing verification

MV-1. There are no unit tests for Ref construction, validation, equality,
serialization, or stable round trips.

MV-2. There is no contract test that proves one exact Ref is used without loss
or reinterpretation by Registry, persistence, Directives, remote placement, and
Plugin runtime contexts.

MV-3. There is no test for namespace stability after an instance module rename,
process restart, instance restart, or node replacement.

MV-4. There is no test that the Agent module can change or be resolved from a
checkpoint without changing the persistence identity. Current behavior forbids
this because the module is in the key and load contract.

MV-5. There is no passing test for cluster-exclusive live ownership. The only
test is explicitly skipped. Existing tests prove stale-write conflict after a
newer commit, not exclusive activation.

MV-6. There is no test for Ref-based delivery after a PID changes, location
cache becomes stale, target node disconnects, or the Agent moves to another
node. Current distributed tests use a known remote PID or parent-owned PID
record.

MV-7. There is no migration test for existing persistence keys and records when
the proposed namespace Ref replaces `{instance, module, partition, id}`.

MV-8. There is no compatibility test for current non-string partition values if
the proposed validation becomes string-only.

## Narrow dependency notes

- Agent definition and checkpoint: The Ref must not enter the neutral Agent
  definition. The checkpoint must keep enough module and definition revision
  data to restore the Agent that the Ref identifies.
- Jido instance: The instance must own namespace configuration and local
  namespace-to-runtime binding. Equal IDs in different namespaces must remain
  separate.
- Persistence: The persistence seam must replace its module-based key with the
  canonical Ref, or the identity design must explicitly retain the module in
  durable identity. Migration must be decided before this change.
- Agent Server and Registry: Local registration can still use a Registry, but
  reservation and lookup must derive from the same canonical Ref. PID and
  activation ID must remain runtime data.
- Runtime topology: Explicit node placement can remain a location request. It
  must not become part of stable identity. Parent PID, spawn reference, and
  request generation remain private activation-control data.
- Signal dispatch: Jido core can resolve a Ref to a current server and then use
  `jido_signal` transport. A generic Agent-directory policy must not be added to
  `jido_signal` without a separate package-boundary decision.
- Durable authority: Current compare-and-swap is useful conflict detection, but
  it is not a live-owner claim. The authority contract must stay separate from
  identity and location.

## Ordered recommendations

The following items are proposals, not current behavior.

1. Lock the release decision first: either require stable namespace identity for
   V3, or state that it is deferred and keep the module-scoped current API.
2. If the seam is in V3, define the small `Jido.Agent.Ref` public contract. Lock
   field types, validation, serialization, and the rule that node, PID, module,
   definition revision, and activation ID are not Ref fields.
3. Add a stable namespace callback to each Jido instance. Define duplicate
   namespace behavior and the local namespace-to-instance binding before public
   Ref APIs are added.
4. Decide partition compatibility. Prefer an explicit migration period if atom
   and integer partitions must become strings.
5. Define one identity conversion boundary. Registry keys, persistence records,
   relationship records, Plugin contexts, and remote spawn requests must receive
   or derive from the same Ref. Do not keep parallel public identity shapes.
6. Decide and implement the persistence-key migration before removing the Agent
   module or instance module from durable keys. Include collision checks and
   rollback rules.
7. Add Ref-first local instance operations. Keep any PID functions clearly
   marked as runtime observation or low-level control. Make each Ref delivery do
   a fresh local resolution.
8. Keep remote placement separate from identity. Add transport resolution only
   after local Ref behavior is complete and verified.
9. Define durable activation authority separately. If V3 promises one live
   owner, implement a claim, lease, or fencing service and enable the skipped
   exclusive-owner test. If V3 promises only stale-write protection, state that
   limit in the public contract.
10. Add the verification listed above, in this order: Ref value tests, local
    Registry and instance tests, persistence migration tests, restart tests,
    cross-node movement tests, stale-location tests, and authority tests.

## Evidence references

- Seam proposal: `docs/design/03_agent-identity/README.md:1-59`.
- Canonical Agent value and checkpoint: `lib/jido/agent.ex:1-10`,
  `lib/jido/agent.ex:94-135`, and `lib/jido/agent.ex:370-423`.
- Jido instance facade and local Registry: `lib/jido.ex:70-201` and
  `lib/jido.ex:347-370`.
- Current local identity APIs: `lib/jido.ex:417-425` and
  `lib/jido.ex:431-586`.
- Agent Server identity options and Registry keys:
  `lib/jido/agent_server/options.ex:11-20`,
  `lib/jido/agent_server/options.ex:247-292`, and
  `lib/jido/agent_server.ex:295-310`.
- Current persistence key and record: `lib/jido/persistence.ex:59-160` and
  `lib/jido/persistence.ex:248-383`.
- Local process-restart checkpoint:
  `lib/jido/agent_server/runtime_checkpoint.ex:1-50`.
- Remote placement and request control:
  `lib/jido/agent_server/directive_runtime.ex:244-418`,
  `lib/jido/agent_server/child_placement.ex:1-160`, and
  `lib/jido/agent_server/spawn_registry.ex:1-140`.
- Existing local identity and partition tests: `test/jido/instance_test.exs:130-216`.
- Existing checkpoint identity tests:
  `test/jido/persistence/checkpoint_identity_test.exs:14-32`.
- Existing cross-node identity and authority tests:
  `test/jido/agent_server/distributed_child_test.exs:11-117` and
  `test/jido/agent_server/distributed_authority_test.exs:10-51`.
- Implemented remote-child limits:
  `docs/design/10_runtime-topology/remote-owned-children.md:65-77`.
