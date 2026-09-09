# Extension boundaries

Jido is a local Agent library. It coordinates public contracts from Jido
Action and Jido Signal. It does not own application architecture, durable
workflow recovery, cluster policy, transport gateways, AI policy, or browser
sessions.

Use ordinary Elixir and OTP composition first. Use a Jido extension contract
only when the extension needs the authority that the contract supplies.

## Select an extension type

| Need | Use | Owner and limit |
| --- | --- | --- |
| Add an application facade, policy, supervision tree, or coordination service | Ordinary Elixir and OTP | The host application owns it. It calls documented public APIs. |
| Define executable work | `Jido.Action` or a Flow through `Jido.Exec` | Jido Action owns execution. Jido owns Agent evaluation and commit. |
| Define, route, or deliver an event | Jido Signal values, routes, dispatch, or buses | Jido Signal owns the event and delivery contracts. |
| Add reusable Agent state or lifecycle behavior | `Jido.Plugin` | A Plugin uses only its declared state, callbacks, Directives, and optional runtime child. |
| Replace one external infrastructure operation | The narrow adapter for that package | The package that defines the operation owns the adapter. There is no universal Jido adapter. |
| Add static Agent or Topology syntax | `Jido.Agent.Extension` or `Jido.Topology.Extension` | The extension lowers syntax to a canonical value before runtime activation. |
| Request runtime work after an Agent commit | `Jido.Agent.Directive` | The runtime handles a typed Directive after commit. A Directive is not a durable delivery guarantee. |
| Observe Agent behavior | `Jido.Observe.Tracer` or a Telemetry handler | Observation has no authority to change evaluation, commit, or runtime results. |

Builders and codecs are public authoring tools. Use them for trusted systems
that create Agent or Topology definitions. The `spawn_fun` option is a public
application boundary for starting an owned child on a known Erlang node. It is
not a cluster placement service.

## Package ownership

Jido uses [Jido Action](https://hexdocs.pm/jido_action/) for Actions,
Instructions, Flows, and in-memory execution. Put reusable executable work in
an Action package or in an application Action module.

Jido uses [Jido Signal](https://hexdocs.pm/jido_signal/) for Signal values,
serialization, routing, dispatch, and the local Signal bus. Put transport
integration at that boundary.

Jido owns Agent values, Turn use of the lower packages, Plugin composition,
candidate assembly, live commit, Directives, the local Agent runtime,
persistence record meaning, static local Topology, public errors, and semantic
Agent observation.

Focused integration packages can own AI behavior, browser automation, storage
providers, recovery services, cluster placement, or transport. They must use
the public contract of the package that owns each operation. They must not
change Jido semantics through private state or messages.

The host application owns external clients, supervision, authorization,
business transactions, deployment, and product policy. When an adapter uses a
database, Redis, or another client process, the host application supervises
that client.

## Public and internal contracts

An extension can use a module or function when it has public documentation and
documented result behavior. It must not use a module or function that has
`@moduledoc false` or `@doc false`.

These types are internal implementation details:

- <code>Jido.Plugin.Spec</code>
- <code>Jido.AgentServer.ChildInfo</code>
- <code>Jido.AgentServer.ParentRef</code>
- <code>Jido.RuntimeStore</code>

Use the public Plugin declaration, Plugin callback contexts, AgentServer
inspection maps, relationship functions, and Jido instance helpers instead.
Instance name helpers are public for application composition and observation.
They do not make an internal process or store API public.

An ecosystem package must not:

- read or change private AgentServer state;
- send private AgentServer messages;
- require a generated supervisor or Registry name;
- change Agent or Plugin state outside Turn evaluation;
- dispatch runtime-owned work before commit;
- treat a PID or OTP name as durable Agent identity;
- depend on an ETS table layout.

## Persistence boundary

`Jido.Persistence.Adapter` is a byte-store contract. Jido owns checkpoint
validation, record meaning, revision policy, and the effect of a storage result
on Agent commit. An adapter owns only its storage operations.

The ETS, File, and Redis adapters remain supported in Jido V3. Instance
persistence defaults and per-Agent selection also remain supported. A future
move or restriction needs an approved migration with compatibility evidence.

Plugin runtime resources do not belong in checkpoints. Keep processes,
connections, watchers, and worker pools in the supervised runtime. Keep only
portable configuration and rebuild data in Plugin state.

## Extension growth

These boundaries can grow as the ecosystem grows. A new extension contract
must have one owner, one authority, documented input and output, error rules,
and executable acceptance evidence. It must protect a shared semantic rule
that ordinary composition cannot protect.

Do not add a generic hook or expose a private implementation to support one
integration. Start with a small integration example. Add the smallest public
contract that the example proves is necessary.
