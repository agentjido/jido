# Agent evolution contract

Status: implementation specification, 2026-10-17.

## Public data API

```elixir
alias Jido.Agent
alias Jido.Agent.Directive, as: D
alias Jido.Persistence

definition = Agent.define!(%{name: "counter", schema: schema, routes: routes})
agent = Agent.instantiate!(definition, id: "counter-1", state: %{})
{:ok, candidate, diff} = Agent.mutate(agent, changes)
{:ok, candidate, returned_directives} = Agent.cmd(agent, signal)
Agent.definition(candidate)
Agent.schema(candidate) # Domain and Plugin fields.
Agent.validate(candidate)
Agent.Diff.between(agent, candidate)
Agent.Diff.empty?(diff)
Agent.Diff.changed?(diff, :routes)
```

## Boundary

`Jido.Agent` is data. A mutation returns a validated candidate and a Diff. It
must not start processes, dispatch Signals, or write storage. AgentServer owns
admission, commit and reconciliation. Its supervisor owns process changes.

## Directives

Use noun_verb constructors. `emit` remains the output primitive.

```elixir
D.agent_add(name, definition, count: 1, initial_state: %{})
D.agent_update(name, fields)
D.agent_replace(name, definition, opts)
D.agent_remove(name)
D.route_add(path, handler, opts)
D.route_add(path) # Pass-through.
D.route_update(path, fields)
D.route_replace(path, handler, opts)
D.route_remove(path)
D.routes_reorder(paths)
D.routes_set(routes)
D.connection_add(path, from: source, to: destination, delivery: :single)
D.connection_update(path, from: source, to: destination, changes: fields)
D.connection_replace(path, from: source, to: destination, delivery: :broadcast)
D.connection_remove(path, from: source, to: destination)
D.topology_set(topology)
D.plugin_add(module, options, initial: value)
D.plugin_configure(module, options, migrate: {module, function, args})
D.plugin_remove(module, state: :discard)
```

Each operation has an explicit Directive struct. Shared collection editing is
private implementation, not another stored authoring format. Runtime process
and addressed-delivery operations belong to `Jido.AgentServer.Directive`.

```elixir
alias Jido.AgentServer.Directive, as: R
R.agent_start(definition_or_instance, name, node: node(), restart: :transient)
R.agent_stop(name, reason)
R.process_start(child_spec)
R.server_stop(reason)
R.signal_send(signal, pid, delivery_mode: :async, timeout: 5_000)
R.owner_send(signal) # OTP process relationship only.
R.agent_send(name, signal) # OTP process relationship only.
R.error_report(error, context)
```

## Mutation and Diff

`Agent.mutate(agent, directives)` returns `{:ok, candidate, diff}` or a structured
error. It accepts mutation directives only. The Turn runner uses the same engine
after handler results and Plugin reduction. It filters runtime directives before
calling the mutation API. `Agent.cmd` retains its existing three-element result.

Apply edits in order. Add requires absence and appends. Update requires presence,
shallow-merges fields and preserves identity and position. Replace requires
presence, replaces the declaration with normalized defaults and preserves its
position. Remove requires presence and does not cascade. Routes use path identity;
agents use name; connections use `{from, to, path}`; Plugins use module identity.
Identity changes require remove plus add. Route reorder lists every current path
exactly once. Final reference checks permit temporary gaps inside a batch.
Validate the complete final state and definition. Errors include mutation index
for operation failures and field path for final validation failures.

`Agent.Diff.between(before, after)` reports final semantic changes to agents,
routes, connections and provider contributions. Each collection reports added,
removed, updated before/after pairs, and before/after identity order. It also
reports state changes. Its `fields` Map reports changes to top-level fields,
including schema, version and origin, during a full upgrade. No PIDs, restart
decisions, or child specs occur in Diff.
Add followed by remove has no net change. A route reorder remains visible.
Diff does not decide whether a runtime process must restart.

```elixir
%Agent.Diff{
  fields: %{vsn: %{before: 1, after: 2}}, # Empty for collection-only mutations.
  agents: %{added: [member], removed: [], updated: [], order: %{before: [], after: [:worker]}},
  routes: %{added: [], removed: [], updated: [%{before: old, after: new}], order: %{before: ["run"], after: ["run"]}},
  connections: %{added: [], removed: [], updated: [], order: %{before: [], after: []}},
  extensions: %{added: [], removed: [], updated: [], order: %{before: [], after: []}},
  state: %{before: old_state, after: new_state} # nil if equal.
}
```

The current Turn retains its selected route and emission contract. Route changes
affect subsequent Turns. Accepted outputs use the candidate connections. Dynamic
routes do not generate or remove Elixir module helper functions.

Plugin changes retain state ownership, explicit discard, migration and callback
order. A batch cannot change a Plugin and use its owned runtime Directive.
Domain schema, identity and descriptive fields have no mutation directives.
A full definition/state upgrade is a separate explicit operation.

## Snapshots and provenance

Save the complete accepted Agent definition and state together. One record
revision identifies both. A module is origin data; restore must not call its
current definition or replace saved fields. Resolve nested Agent definition
modules into saved definition values. Save schemas as data or immutable trusted
references, and code as immutable trusted references. Never silently substitute
newer executable or provider code. Retain referenced code for supported snapshots.

Public `Persistence.snapshot/2` and `restore/2` use a versioned portable envelope.
Storage uses native portable Elixir data. Static schemas are embedded; storage
needs no Registry. The separate JSON authoring API retains its trusted Registry.
Saved code fingerprints must match at restore. Plugin conversion remains owned by the
existing persistence callbacks. The storage checkpoint path captures the full
Agent and uses the same definition-freezing and validation rules. It does not
recover routes, topology, schema or extensions from an Agent source module.
Complete custom state callbacks may convert state, but cannot replace definition
provenance. No callback may be required merely to recover a current definition.

```elixir
{:ok, snapshot} = Persistence.snapshot(candidate, context: %{})
%{
  format: 1,
  agent: %Agent{}, # Complete definition and converted state; nested definitions are values.
  references: %{MyAction => <<_::128>>, MyPlugin => <<_::128>>},
  state_format: :default # Or :custom for complete state conversion callbacks.
} = snapshot
{:ok, restored} = Persistence.restore(snapshot, context: %{})
```

The manifest includes declared handlers, nested Flow calls, executable schema
references, state schema references, providers, runtime support modules and
custom state callbacks. Fingerprints identify code; they do not retain it.
Deployments must retain a compatible code release, including arbitrary helper
code called inside functions. Source Agent modules are provenance unless their
callbacks or schemas are required. Earlier checkpoint formats need explicit
conversion. Do not silently load them through the current module definition.

An Agent snapshot includes its own state and topology intent. It does not include
the live state of other running Agents. A coordinated multi-Agent snapshot is
outside this contract. Snapshot and restore must perform no process operations.

## Upgrade Actions

`Persistence.upgrade(snapshot, action, context: %{})` validates the envelope,
runs an explicit Action with `%{snapshot: snapshot}`, resolves target references,
and validates the full target Agent. The success output is `%{snapshot: value}`.
No returned Directives are permitted. It does not require resolving old handlers
before the Action. Agent id and origin module must remain equal; both are fixed
headers for a stored record lifetime. Upgrades can change schemas, handlers and
versions while they retain origin provenance. Old snapshot data remains
unchanged. Saving the result is a separate normal compare-and-swap operation.
Upgrade Actions must be deterministic data conversion with no external I/O.
The executor cannot prove absence of arbitrary Action I/O; this is an author
contract. Restore never selects or runs an upgrade automatically.

```elixir
defmodule UpgradeCounter do
  use Jido.Action, name: "upgrade_counter"

  def run(%{snapshot: old}, _context) do
    target = %{MyCounter.definition() | id: old.agent.id, state: %{count: old.agent.state.total}}
    with {:ok, snapshot} <- Jido.Persistence.snapshot(target),
      do: {:ok, %{snapshot: snapshot}}
  end
end

{:ok, upgraded} = Persistence.upgrade(old_snapshot, UpgradeCounter)
:ok = Persistence.save_agent(store, upgraded, namespace: "app", expected_revision: revision, revision: revision + 1)
```

## Live AgentServer boundary

```elixir
%{agent: accepted, state_version: revision} = Jido.AgentServer.snapshot(server)
{:ok, portable} = Persistence.snapshot(accepted)
{:ok, upgraded, []} = Jido.AgentServer.upgrade(server, UpgradeCounter, context: %{})
:ok = Jido.AgentServer.await_ready(server)
```

The live snapshot reads the accepted Agent and revision in one server event.
It contains local runtime values. Use `Persistence.snapshot/2` for portable
conversion. A live upgrade waits behind active work, validates its complete
candidate, and uses the same Plugin quiescence, durable save, checkpoint,
revision and reconciliation path as a Turn. A caller timeout does not cancel it.

All declared agents start under the owning OTP supervisor. Counts and initial
inputs bind from the accepted parent state. A change to copied initial inputs
replaces the affected agent. Count changes retain unchanged slots. Connection
changes retain agent processes. Source outputs use accepted connections;
explicit dispatch retains its addressed delivery. Local Bus declarations own
local Bus resources and subscriptions. Other provider endpoint kinds and remote
Agent startup are rejected before commit. There is no dormant `activate_child`
API. A snapshot contains topology intent, not coordinated child process state.

## Required tests before AgentServer depends on this layer

- Each constructor, operation precondition, unknown fields, immutable identities.
- All handler forms; route defaults, emission contracts and order.
- Current-Turn route contract versus next-Turn routing.
- Ordered multi-collection edits and final-only reference validation.
- Failure atomicity, error index/path, malformed and improper batches.
- Plugin initialization, preservation, disposal, migration and ownership.
- Exact Diff, cancellation, reorder and unchanged collection behavior.
- Equivalent Map, DSL and mutation authoring; JSON round trips.
- Full mutated definition/state snapshot, nested definition freezing, stale source
  module changes, Plugin conversion, unknown or changed references.
- Upgrade before old reference resolution; invalid results, identity changes,
  returned directives, exceptions and unchanged original snapshot.
- Storage revision conflicts preserve original bytes.
- AgentServer commit/recovery retains mutated routes and definitions.
- AgentServer reconciliation preserves unaffected processes; no next Turn before
  readiness; post-commit failure retains committed data.

## Validation evidence

```text
test/jido/agent/mutation/mutation_test.exs       ordered collection and Plugin edits
test/jido/agent/mutation/foundation_test.exs     Diff, invalid data, ownership, API boundary
test/jido/agent/mutation/server_test.exs         leaf commit, failure isolation, local/durable recovery
test/jido/persistence/snapshot_test.exs          provenance, changed source code, references, upgrades, CAS
test/authoring/agents/mutation_test.exs          independent Map/DSL/mutation equality and JSON
```

The AgentServer evolution tests cover live snapshot/revision reads, explicit
schema upgrades, failed upgrade isolation, serial admission, durable recovery,
runtime Agent directives, counted agents, state-bound inputs, connection edits,
local buses, unchanged process identity, readiness and committed startup failure.
Examples remain outside this implementation scope.

## Simplification decisions

Keep one mutation engine and one final Diff; do not store operation logs or a
second definition wrapper. Reuse core route, topology and extension validation.
Remove generic Topology/Plugin Directive containers. Consolidate duplicated
parameter merging and complete-state/schema validation where contracts agree.
AgentServer uses accepted topology declarations directly. Its derived member
plan records the last applied definition and bound initial inputs. It exists
only to retain unaffected processes; it is not another saved definition format.
Runtime constructors use explicit OTP Directive records after commit. The complete-state and schema checks now use
`Agent.Data`. Route parameter merging uses `Agent.Route.params/2`. Plugin data
edits stay inside Mutation; Composition no longer performs a second edit pass.
Topology entry normalization no longer uses empty keyword lists as an indirect
field schema. One entry validator serves authoring and mutation validation.
Remove the unused Interface builder, old Authoring SourceMap and source cache
wrappers. Codec and View resolve the canonical Agent definition directly.
Snapshot code references and JSON Registry identifiers remain external
dependencies. Capture and verify their provenance explicitly.

Retained data indirection:

```text
Spark DSL entries -> one canonical Agent value           authoring only
Agent.extensions -> provider.runtime_support -> Plugins   runtime adapter; specs are not saved
JSON -> trusted Registry identifiers                      external serialization boundary
Snapshot.references -> module code fingerprints           code must remain available
AgentCheckpoint -> Snapshot                               storage/context adapter; one payload format
AgentServer.TopologyRuntime -> bound member plan           runtime comparison only; not saved
```
