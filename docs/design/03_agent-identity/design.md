> Target seam design. This document is pending approval.

# Stable Agent identity design

All requirements and decisions in this document are recommended targets. The
[design review index](../README.md#document-review-status) is the source of
truth for approval. The prerequisite documents are also pending approval.

## Scope and owner

- Owner: `Jido.Agent.Ref` and the Jido Agent identity boundary.
- In scope: stable identity fields, validation, equality, portable encoding,
  persistence-key meaning, and Ref use at public identity boundaries.
- Out of scope: Jido instance configuration syntax, namespace assignment,
  cluster directories, location-cache rules, placement policy, transport,
  persistence record layout, activation transfer, leases, fencing, and
  cluster write authority.
- Adjacent owners: seam 01 owns the Agent value and definition revision. Seam
  07 owns persistence records and key migration. Seams 08 to 10 own live
  resolution, instance binding, and topology behavior. `jido_signal` owns
  general Signal transport.

## Model

The public identity value is:

```elixir
%Jido.Agent.Ref{
  namespace: "my-app/primary",
  partition: nil,
  id: "order-123"
}
```

Its identity tuple is `{namespace, partition, id}`. Namespace and ID are
nonempty binary strings. Partition is `nil` or a nonempty binary string. The
Jido treats these values as exact data. It does not change case, separators,
or content.

The namespace identifies an application-owned Agent identity domain. The
partition separates equal IDs inside that domain. `nil` is the default
partition. One exact tuple identifies one logical Agent.

The Ref answers only this question:

```text
Stable identity:  Who is this Agent?
Runtime location: Where is an activation now?
Write authority:  Which activation can commit?
```

A PID, OTP name, node, module, definition revision, activation ID, state
version, storage revision, lease, and fencing token are not parts of the Ref.
They can change while identity stays the same.

The Ref can cross processes, Jido instance process lifetimes, nodes, storage,
and transport boundaries. Each consumer keeps the exact Ref. A later owner
can resolve it to a location or check write authority. This seam does not
select either method.

## Requirements

### Ref value and identity

`ID-REQ-001`: The Agent identity boundary shall provide one public
`Jido.Agent.Ref` value with `namespace`, `partition`, and `id` fields.

`ID-REQ-002`: When the Agent identity boundary validates a Ref, it shall
require `namespace` and `id` to be nonempty binary strings.

`ID-REQ-003`: When the Agent identity boundary validates a Ref, it shall
require `partition` to be `nil` or a nonempty binary string.

`ID-REQ-004`: When the Agent identity boundary compares two Refs, it shall use
exact equality of their `{namespace, partition, id}` tuples.

`ID-REQ-005`: When a Ref crosses an identity boundary, the identity owner shall
preserve each field without automatic changes.

`ID-REQ-006`: When an Agent process, Jido instance process, instance module,
or Erlang node changes, the Agent identity boundary shall keep the Ref
unchanged.

`ID-REQ-007`: The Agent identity boundary shall exclude Agent module,
definition revision, PID, OTP name, node, activation ID, state version,
storage revision, lease, and fencing data from the Ref.

### Public construction and encoding

`ID-REQ-008`: When `Jido.Agent.Ref.new/1` receives valid Ref attributes, the
Ref boundary shall return `{:ok, ref}`.

`ID-REQ-009`: If `Jido.Agent.Ref.new/1` receives invalid Ref attributes, then
the Ref boundary shall return `{:error, error}` through the approved seam-12
error contract.

`ID-REQ-010`: When `Jido.Agent.Ref.new!/1` receives invalid Ref attributes,
the Ref boundary shall raise the same error returned by `new/1`.

`ID-REQ-011`: When the Ref boundary encodes a Ref as a public map, it shall
produce `%{"version" => 1, "namespace" => namespace, "partition" => partition,
"id" => id}`.

`ID-REQ-012`: When the Ref boundary decodes a valid version-1 public map, it
shall return a Ref that is exactly equal to the encoded Ref.

`ID-REQ-013`: If the Ref boundary decodes an unknown version or an invalid
map, then it shall return `{:error, error}` through the approved seam-12 error
contract.

### Agent, instance, and partition boundaries

`ID-REQ-014`: When a Ref identifies a `%Jido.Agent{}` instance, the identity
boundary shall require `ref.id` to equal the Agent instance ID.

`ID-REQ-015`: When two Agent identities have equal IDs and different
namespaces, the identity boundary shall treat them as different identities.

`ID-REQ-016`: When two Agent identities have equal namespaces and IDs but
different partitions, the identity boundary shall treat them as different
identities.

`ID-REQ-017`: When a Jido instance binds a namespace, the instance boundary
shall keep that namespace independent of its process name and module name.

### Lookup, persistence, delivery, and placement

`ID-REQ-018`: When Jido performs identity-based lookup, it shall use the
complete Ref as the lookup identity.

`ID-REQ-019`: When the persistence boundary makes a durable Agent identity,
it shall use only the complete Ref.

`ID-REQ-020`: When a persistence record stores an Agent module or definition
revision, the persistence boundary shall keep that data outside the record's
Agent identity.

`ID-REQ-021`: When an Agent-to-Agent delivery boundary names its logical
target, it shall carry the complete target Ref.

`ID-REQ-022`: When a placement boundary receives an Agent identity, it shall
preserve the complete Ref separately from the requested location.

`ID-REQ-023`: When a runtime boundary returns a PID, OTP name, node, or other
handle for a Ref, it shall identify that value as a replaceable runtime handle.

`ID-REQ-024`: If location resolution fails or returns stale information, then
the identity boundary shall not change the Ref.

### Compatibility

`ID-REQ-025`: While no approved owner-seam migration removes ID-first or
PID-first public functions, the Jido public API shall keep those functions
supported.

`ID-REQ-026`: While current public partition options accept values other than
binary strings, the Jido public API shall keep those options supported until a
staged conversion has compatibility evidence.

`ID-REQ-027`: When durable storage moves from a legacy key to Ref identity, the
persistence boundary shall detect identity collisions before it writes a new
record.

`ID-REQ-028`: While legacy persistence records remain supported, the
persistence boundary shall provide a documented read and rollback rule for
their module-based keys.

## Public contract

### Value and functions

| Entry | Target contract |
| --- | --- |
| `%Jido.Agent.Ref{}` | Public portable identity value with only `namespace`, `partition`, and `id` |
| `new/1`, `new!/1` | Construct and validate one Ref from a map or keyword list |
| `validate/1` | Return `{:ok, ref}` or the approved validation error |
| `to_map/1` | Return the version-1 string-key map |
| `from_map/1`, `from_map!/1` | Decode and validate the version-1 map |
| Exact equality | Struct equality is identity equality; there is no hidden normalization |

The map is the portable public encoding. The persistence seam can choose a
binary adapter key, but its decoded identity must be the same Ref. String
formatting for logs or user interfaces is not an identity codec unless a later
approved contract defines it.

### Boundary use

| Boundary | Identity input | Data that stays separate |
| --- | --- | --- |
| Agent value | `ref.id` agrees with `agent.id` | Agent module and definition revision |
| Jido instance | Complete Ref | Runtime supervisor name and module |
| Local Registry | Complete Ref | PID and Registry process |
| Persistence | Complete Ref | Record format, module, checkpoint, and storage revision |
| Delivery | Complete target Ref | Resolved PID, node, route, and transport result |
| Placement | Complete Ref | Requested node and placement policy |

The exact Ref-first lifecycle function names and result types belong to seams
08 and 09. Local-only and transport-capable operations belong to seams 09 and
10. The exact persistence record and adapter key belong to seam 07.

## Invariants

- `ID-INV-001`: One exact `{namespace, partition, id}` tuple identifies one
  logical Agent.
- `ID-INV-002`: Identity does not contain runtime location or write authority.
- `ID-INV-003`: Identity does not contain Agent code or definition version.
- `ID-INV-004`: A process restart, instance restart, module rename, or node
  change does not change a Ref.
- `ID-INV-005`: Every portable Ref round trip preserves exact equality.
- `ID-INV-006`: Legacy IDs, partitions, PIDs, names, and storage keys stay
  supported until their owner seam completes an approved migration.

## Downstream guarantees

These guarantees apply only after the related requirements are approved.

| Consumer seam | Guaranteed contract |
| --- | --- |
| 07 Persistence | The complete Ref is durable identity; code and storage revision are separate |
| 08 Agent Server | A Ref is stable across process replacement; a PID is only a handle |
| 09 Jido instance | Namespace binds stable identity without becoming module identity |
| 10 Runtime topology | Placement and location can change without a Ref change |
| 12 Errors and contracts | `agent_ref` can be a bounded error identifier after this value is approved |
| 13 Observability | Events can identify one Agent without recording its PID as identity |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `ID-DEC-001` | What is the Ref tuple? | Use nonempty binary namespace and ID, plus `nil` or a nonempty binary partition. | The value is small, portable, and exact. |
| `ID-DEC-002` | How is a namespace assigned and bound to a Jido instance? | Let seam 09 define explicit application configuration and duplicate binding errors. | Identity stays stable across module and process changes. |
| `ID-DEC-003` | How do current non-string partitions move to the Ref form? | Keep old options and require an explicit, collision-checked conversion before Ref creation. | Existing atom and term partitions do not break at once. |
| `ID-DEC-004` | How does storage move to Ref identity? | Let seam 07 define dual-read, collision, rewrite, rollback, and release gates. | This seam sets identity meaning without setting record layout. |
| `ID-DEC-005` | Which public operations accept or return a Ref? | Add Ref-first lifecycle and inspection paths in seams 08 and 09 before any deprecation. | Current ID and PID APIs stay supported. |
| `ID-DEC-006` | Which operations resolve only local location and which use transport? | Let seams 09 and 10 decide after local Ref behavior has proof. | This seam does not select topology policy. |
| `ID-DEC-007` | Which component owns cluster location and exclusive write authority? | Keep these as separate later contracts outside the Ref. | A Ref does not make an unproved safety promise. |
