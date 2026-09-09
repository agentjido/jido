> Implemented seam alignment. This document records the selected contract and
> its evidence.

# Jido instance alignment

## Status

- Design selected and implemented: 2026-09-10.
- Alignment state: `Implemented`.
- Compatibility state: additive. The ID, PID, partition, generated instance,
  and direct `Jido.AgentServer` APIs remain supported.
- Seam 10 keeps Plugin wrappers in the Agent pool for first-stage V3. Seam 12
  owns broader error normalization. Seam 13 owns observation projections.

## Selected contract

One Jido instance is one application-owned local Supervisor and facade. It
keeps the existing five standard instance children and the `:one_for_one`
strategy. The Jido package application does not start a default application
instance.

An instance can have an optional stable namespace. The namespace is a nonempty
binary. One exact namespace can be bound to only one live local instance on one
Erlang node. The namespace is not a process name, node location, lease, or
write-authority grant.

Ref-first operations require a namespace. They validate the complete
`Jido.Agent.Ref`, require its namespace to equal the instance namespace,
resolve the current local Agent Server, and call only public Agent Server
functions. They do not route to a remote node or start a missing Agent.

Instance configuration remains a keyword list. A generated instance resolves
the compile-time declaration, application configuration, and explicit runtime
options in that order. Jido validates the final instance-owned values before it
starts an instance child.

## Canonical implementation

| Contract | Source |
| --- | --- |
| Final keyword validation for `name`, `otp_app`, `namespace`, `max_tasks`, and `persistence` | `Jido.Instance.Options` |
| Atomic local namespace claim, binding, release, and worker-restart recovery | `Jido.Instance.NamespaceRegistry` |
| Complete Ref validation, local resolution, and public Agent Server delegation | `Jido.Instance.RefFacade` |
| Generated and root Ref-first API families | `Jido` |
| Namespace input to Agent Server persistence and activation preflight | `Jido.AgentServer` and `Jido.Topology.Controller.Activation` |
| Stable namespaced key and record format 3 | `Jido.Persistence` and `Jido.Persistence.Record` |
| Package-level namespace binder, but no global Jido instance | `Jido.Application` |

The public Ref-first family has these entries:

| Role | Entries |
| --- | --- |
| Identity and resolution | `agent_ref`, `resolve_agent` |
| Publication | `start_agent_ref`, `activate_agent` |
| Command | `call`, `cast`, `send_request`, `receive_response` |
| Control | `cancel`, `cancel_turn`, `attach`, `detach`, `touch` |
| Lifecycle | `stop_agent_ref`, `hibernate_ref`, `delete_agent` |
| Inspection | `agent`, `plugin_state`, `status`, `snapshot`, `children`, `await_ready`, `set_agent_debug`, `recent_events` |

Generated modules that use `Jido` provide the same roles with their instance
argument bound. They name the ownership controls `attach_ref`, `detach_ref`,
and `touch_ref`. An instance without a namespace can still use all compatible
ID and PID functions. A Ref-first function returns
`:jido_namespace_required` for that instance.

## Persistence identity and migration

Unnamed instances keep the legacy key and record format 2. A namespaced write
uses a stable key derived from `{namespace, partition, id}` and record format 3.
The Agent module and local instance atom are not part of the new key. The
record still stores the Agent module and validates it during restore.

For a namespaced operation, Jido probes both the stable Ref key and the
compatible legacy key:

- If neither key exists, Jido uses the stable Ref key.
- If only the stable key exists, Jido uses the stable key.
- If only the legacy key exists, Jido continues to read and write that legacy
  key.
- If both keys exist, Jido returns
  `{:persistence_identity_collision, details}` and does not select one.

Jido does not rewrite or remove a legacy key automatically. The adapter
contract supplies compare-and-swap for one key. It cannot atomically move data
between two keys. For this reason, adding a namespace is an application
migration gate. Stop old writers, check for collisions, and then enable the
namespaced runtime.

Compatible keys also contain the Agent module, and the adapter has no key-list
contract. Core cannot discover a second legacy module key that would collapse
to the same Ref. The application must inventory that case before cutover.

An older runtime cannot read format 3 or the stable Ref key. Downgrade after a
first namespaced write is not supported. Probe-before-write also does not make
concurrent old and new releases safe across two keys.

Durable delete is logical. `delete_agent` refuses a live local Server and then
uses the seam-07 compare-and-swap tombstone contract. Physical purge stays an
adapter or operator operation.

## Evidence

| Requirement group | Evidence | State |
| --- | --- | --- |
| `INST-REQ-001` to `INST-REQ-007` | Existing instance, helper, and supervisor tests | `Proven` |
| `INST-REQ-008`, `INST-REQ-009`, `INST-REQ-037`, `INST-REQ-038`, `INST-REQ-041`, `INST-REQ-043` | Invalid direct and generated configuration fails before child startup in `instance_ref_test.exs` | `Proven` |
| `INST-REQ-010` to `INST-REQ-013` | Exact namespace, duplicate binding, claim release, idempotent startup, and registry-worker restart tests | `Proven` |
| `INST-REQ-014` to `INST-REQ-026` | Instance supervision, runtime-store lifetime, startup, ownership, and lifecycle tests | `Proven` |
| `INST-REQ-027` to `INST-REQ-036` | Ref facade call, cast, OTP request, missing Ref, wrong namespace, and stop tests | `Proven` |
| `INST-REQ-039`, `INST-REQ-040` | Public inventory and normal OTP composition | `Proven` |
| `INST-REQ-042`, `INST-REQ-044`, `INST-REQ-045` | Existing override tests plus durable Ref rebind, activation, hibernate, and tombstone delete tests | `Proven` |
| `INST-REQ-046` to `INST-REQ-053` | Existing lookup, inspection, debug, ownership, and independent-limit tests plus Ref delegates | `Proven` |
| `INST-REQ-054` to `INST-REQ-056` | Exact local namespace binding and no transport or Topology fallback in `RefFacade` | `Proven` |
| Stable reference proof | FA03 now runs three executable tests, including durable namespace rebinding | `Proven` |

## Compatibility decisions

| Area | Decision |
| --- | --- |
| Instance startup | Keep module instances, plain atom instances, `Jido.Default`, and standard OTP child specifications. |
| Local names | Keep atom-derived service names. A namespace does not rename an OTP service. |
| Namespace | Keep it optional for compatible APIs and required for Ref-first APIs. |
| Partition | Keep current term-valued compatible APIs. A Ref keeps the seam-03 binary-or-`nil` field. |
| Registry | Keep the existing local Agent registration key. The Ref facade checks the namespace before it resolves the compatible local key. |
| PID and Server APIs | Keep current results and public Agent Server functions. |
| Persistence | Keep the instance default and explicit per-Agent override or disablement. |
| Runtime checkpoint | Keep latest-commit recovery during one instance lifetime. |
| Callbacks | Keep overridable `config/1`. Add no child, admission, or lifecycle callback. |
| Topology | Keep Ref resolution local. Add no implicit controller or transport fallback. |

## Deferred work

- Seam 10 keeps Plugin runtime wrappers in the Agent Dynamic Supervisor. It
  keeps the owner-built Plugin child specification and restart contracts.
- Seam 12 can normalize more compatibility results. This seam has stable codes
  for invalid instance configuration, duplicate namespace, missing namespace,
  and namespace mismatch.
- A future migration tool can copy one legacy record to one stable Ref key. It
  must have an explicit offline or provider-specific atomicity contract.

## Completion criteria

- [x] Final instance configuration fails before child startup when invalid.
- [x] Exact namespace binding is local, unique, idempotent, and recoverable
      after a namespace registry worker restart.
- [x] A failed startup releases its namespace claim.
- [x] Ref-first command, control, lifecycle, and inspection roles use public
      Agent Server functions.
- [x] Current ID, PID, partition, persistence, debug, and direct Server APIs
      remain supported.
- [x] Durable Ref state survives a local instance name change.
- [x] Ref persistence detects a legacy and stable-key collision.
- [x] The migration text states the non-atomic cross-key and downgrade limits.
- [x] The migration text assigns legacy module-key inventory to the
      application.
- [x] The stable reference research example is executable and has no skip.
- [x] No instance API claims transport, placement, cluster authority, or
      topology control.
