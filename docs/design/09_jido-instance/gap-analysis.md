# Jido instance gap analysis

> Review report. This document is pending approval.

## Scope and owner

This report reviews the Jido instance seam only. The seam owner is the `jido`
package. It owns the local instance supervisor, instance identity,
configuration, application facade, local isolation, and instance persistence
selection. Agent behavior stays in `Jido.Agent`. Live Agent execution stays in
`Jido.AgentServer`. Storage mechanics stay in `Jido.Persistence` and its
adapters.

The main evidence is implemented code under `lib`. Tests and public module or
guide text show which implemented contracts have verification and user-facing
documentation. The files in this design folder are proposals unless they say
that a statement describes the current SDK.

This report does not review the complete Agent Server, Plugin, topology,
observability, or persistence designs. It includes these seams only where the
Jido instance calls them or owns their processes.

## Implemented baseline

The following items are current facts.

1. `use Jido` requires `:otp_app` at compile time. It accepts an optional
   compile-time `:persistence` declaration. It generates `child_spec/1`,
   `start_link/1`, keyword-list `config/1`, Agent lifecycle helpers, runtime
   name helpers, and debug helpers. The application environment is read with
   the instance module as the key. Runtime options override that environment
   value. `config/1` is overridable. See `lib/jido.ex:94-142` and
   `lib/jido.ex:144-229`.
2. A plain Jido instance requires an atom in `:name`. That atom is both the
   local Supervisor name and the root used to derive Registry, Task Supervisor,
   Runtime Store, Spawn Registry, and Agent Supervisor names. See
   `lib/jido.ex:318-370` and `lib/jido.ex:380-415`.
3. The instance uses a `:one_for_one` Supervisor. Its children, in order, are
   Task Supervisor, Registry, Runtime Store, Spawn Registry, and one dynamic
   Agent Supervisor. See `lib/jido.ex:346-370`.
4. `start_agent` merges the selected instance atom into Agent Server options
   and starts the Server under the instance Agent Supervisor. It returns a PID.
   The Registry key is the Agent ID plus an optional partition. See
   `lib/jido.ex:431-485`, `lib/jido/agent_server.ex:103-145`, and
   `lib/jido/agent_server.ex:2981-2988`.
5. The generated facade starts, stops, finds, lists, counts, hibernates, and
   thaws Agents. Stop and hibernate accept a PID or another Server reference.
   Lookup accepts an ID and returns a PID or `nil`. Command, inspection,
   cancellation, attachment, and touch functions remain public PID-based
   `Jido.AgentServer` functions. See `lib/jido.ex:144-185`,
   `lib/jido.ex:487-684`, and `lib/jido/agent_server.ex:160-348`.
6. Instance-local live isolation uses separate derived Registries and Runtime
   Stores. Partitions add a second local key scope. Persistence record keys use
   the instance atom, Agent module, partition, and Agent ID. See
   `lib/jido.ex:386-420`, `lib/jido/runtime_store.ex:83-129`, and
   `lib/jido/persistence.ex:153-159`.
7. An Agent inherits the instance module's compile-time persistence adapter
   when it has no `:persistence` startup option. An Agent startup option can
   select another adapter or disable persistence. Adapter declarations and
   adapter callbacks are validated when Agent Server options are built. See
   `lib/jido/agent_server/options.ex:377-405` and
   `lib/jido/persistence.ex:27-57`, `lib/jido/persistence.ex:162-231`.
8. A nonpersistent Agent Server writes committed Agent state and version to the
   instance Runtime Store. An abnormal restart restores that runtime
   checkpoint. A configured persistent Server loads durable state according to
   `restore: false | :if_found | :required`. See
   `lib/jido/agent_server/runtime_checkpoint.ex:8-50` and
   `lib/jido/agent_server.ex:2874-2929`.
9. Plugin runtime wrappers start in the same dynamic Agent Supervisor as Agent
   Servers. The Agent Server tracks and stops these wrappers. There is no
   instance Plugin runtime pool. See
   `lib/jido/agent_server/plugin_lifecycle.ex:101-155` and
   `lib/jido/agent_server/plugin_lifecycle.ex:169-226`.
10. The package Application starts only an empty `Jido.Supervisor` after
    Telemetry setup. Applications must add their own Jido instance to their
    supervision tree. See `lib/jido/application.ex:1-9` and the public guidance
    in `guides/deployment-and-shutdown.md:3-26`.

## Aligned contracts

These design statements match current behavior.

- The application owns and supervises a named Jido instance. The generated
  module is the local Supervisor name. See
  `docs/design/09_jido-instance/jido-instance.md:14-34`,
  `lib/jido.ex:14-29`, and `test/jido/instance_test.exs:218-225`.
- Instance configuration uses `config otp_app, InstanceModule` and explicit
  runtime options take precedence. See
  `docs/design/09_jido-instance/jido-instance.md:89-99`,
  `lib/jido.ex:129-140`, and `test/jido/instance_test.exs:95-118`.
- Instance-supervised Agent startup does not make the original caller the link
  owner. Direct `Jido.AgentServer.start_link/1` does link to its caller. See
  `docs/design/09_jido-instance/jido-instance.md:42-54`,
  `lib/jido/agent_server.ex:85-119`, and
  `test/jido/agent_server/startup_test.exs:138-158`.
- Startup validates keyword options, requires a nonempty string ID when an ID
  is supplied, and rejects overrides of an existing Agent instance. See
  `docs/design/09_jido-instance/jido-instance.md:56-60`,
  `test/jido/agent_server/startup_test.exs:132-135`, and
  `test/jido/agent_server/options_test.exs:50-64`.
- Separate instance atoms produce separate local names and Registries. Equal
  Agent IDs can also be isolated by partition. See
  `docs/design/09_jido-instance/jido-instance.md:181-197`,
  `lib/jido.ex:386-420`, and `test/jido/instance_test.exs:206-216`.
- Persistence is optional. External resources such as Redis are not children of
  the Jido instance. See `docs/design/09_jido-instance/jido-instance.md:79-85`,
  `lib/jido.ex:70-77`, and `guides/configuration.md:7-27`.
- Instance Runtime Store data is not durable across a complete instance stop.
  Its ETS table does survive a Runtime Store worker restart because the
  instance Supervisor owns the table. See
  `docs/design/09_jido-instance/jido-instance.md:207`,
  `lib/jido/runtime_store.ex:5-22`, and
  `test/jido/runtime_store_test.exs:167-190`.
- The callback analysis correctly describes the current fixed child set,
  overridable `config/1`, lack of custom instance children, and lack of an
  instance admission callback. See
  `docs/design/09_jido-instance/instance-callbacks.md:15-28` and
  `lib/jido.ex:94-142`, `lib/jido.ex:346-370`.

## Gaps

### Missing implementation

The following items are proposals that have no canonical implementation.

1. There is no required stable `namespace`, no `Jido.Agent.Ref`, and no
   `agent_ref/2`. `use Jido` reads only `:otp_app` and `:persistence`. Durable
   identity still contains the local instance atom. See the proposal in
   `docs/design/09_jido-instance/jido-instance.md:38-40` and
   `docs/design/09_jido-instance/jido-instance.md:128-167`, compared with
   `lib/jido.ex:94-107` and `lib/jido/persistence.ex:153-159`.
2. There is no `Jido.Instance.Config` struct or complete Zoi validation at
   instance startup. `config/1` returns an open keyword list. Only the
   components that consume options validate selected values. See the proposal
   in `docs/design/09_jido-instance/jido-instance.md:87-122`, compared with
   `lib/jido.ex:109-140` and `lib/jido.ex:346-370`.
3. The full Ref-based instance facade is absent. There are no generated
   `activate_agent`, `call`, `cast`, asynchronous request, cancellation,
   durable delete, Agent inspection, Plugin inspection, commit,
   `plugin_runtimes`, attach, detach, or touch functions. See
   `docs/design/09_jido-instance/jido-instance.md:124-176`, compared with
   `lib/jido.ex:144-229`. The current public guide explicitly directs users to
   PID-based Agent Server operations at `guides/core-scope.md:7-21` and
   `guides/runtime.md:1-26`.
4. There is no separate Plugin runtime pool. Plugin wrappers use the Agent
   Supervisor. See the proposed topology at
   `docs/design/09_jido-instance/jido-instance.md:62-77`, compared with
   `lib/jido/agent_server/plugin_lifecycle.ex:145-155`.
5. There is no instance persistence callback pair, persistence Record, or
   instance-level persistence timeout. The current implementation uses a
   binary adapter declaration and direct adapter calls. The adjacent design
   marks its callback contract as deferred. See
   `docs/design/07_persistence/instance-persistence.md:1-14` and
   `docs/design/07_persistence/instance-persistence.md:108-138`, compared with
   `lib/jido/persistence.ex:1-16` and `lib/jido/persistence.ex:75-149`.
6. There are no `children/1`, `configure/1`, or `admit_agent/2` instance
   callbacks. There is also no instance behavior that declares optional
   callbacks. See `docs/design/09_jido-instance/instance-callbacks.md:30-106`
   and `docs/design/09_jido-instance/instance-callbacks.md:126-140`.

### Design and code conflict

These are not only absent features. Current behavior gives a different
contract.

1. The design requires a unique, nonempty namespace. Current code does not read
   or validate `:namespace`. It uses the local module or instance atom in live
   names and durable keys. A durable identity therefore changes when the same
   proposed namespace is rebound to another local instance atom. The skipped
   acceptance test records this failure at
   `test/examples/99_research/99_11_stable_reference/stable_reference_test.exs:60-79`.
2. The design topology uses `:rest_for_one`, puts Registry before task
   supervision, and separates Agent and Plugin pools. Current code uses
   `:one_for_one`, starts Task Supervisor before Registry, adds Runtime Store
   and Spawn Registry, and has one dynamic pool. See
   `docs/design/09_jido-instance/jido-instance.md:62-77` and
   `lib/jido.ex:346-370`.
3. The design says that Plugin runtime hosts never enter the Agent pool.
   Current Plugin runtime wrappers do enter the dynamic Agent Supervisor. See
   `docs/design/09_jido-instance/jido-instance.md:201-206` and
   `lib/jido/agent_server/plugin_lifecycle.ex:145-155`.
4. The design makes `Jido.AgentServer` internal and makes the instance facade
   the only command API. Current public module documentation and guides support
   direct PID-based Agent Server calls. See
   `docs/design/09_jido-instance/jido-instance.md:159-176`,
   `lib/jido/agent_server.ex:1-35`, and `guides/runtime.md:1-23`.
5. The design says that `start_agent/2` returns an Agent Ref. Current code and
   tests return a PID. See
   `docs/design/09_jido-instance/jido-instance.md:159-167`,
   `lib/jido.ex:144-149`, and `test/jido/instance_test.exs:183-203`.
6. The instance persistence proposal says that all Agents in one instance use
   the same provider and that one Agent cannot select another adapter. Current
   Agent startup options can override or disable the inherited instance
   adapter. See `docs/design/07_persistence/instance-persistence.md:16-23` and
   `lib/jido/agent_server/options.ex:377-389`.
7. The design says that a nonpersistent Agent Server restart resets to the
   complete initial Agent. Current code restores the last committed runtime
   checkpoint. The runtime lifecycle test verifies the current restore
   behavior after a Plugin failure. See
   `docs/design/09_jido-instance/jido-instance.md:207-210`,
   `lib/jido/agent_server/runtime_checkpoint.ex:11-31`, and
   `test/jido/agent_server/runtime_lifecycle_test.exs:293-327`.
8. The design configuration includes `persistence_timeout` and a closed
   observability map. Current instance startup does not consume either value as
   one validated config. Observability has its own resolution rules. See
   `docs/design/09_jido-instance/jido-instance.md:101-122` and
   `guides/configuration.md:89-106`.

### Missing decision

The following questions must have a decision before implementation.

1. Decide whether stable namespace and `Jido.Agent.Ref` are required for the V3
   release. If they are required, define the migration period in which PID and
   Ref APIs can coexist. The stable identity design still lists this release
   question as open at `docs/design/03_agent-identity/README.md:52-59`.
2. Decide whether the implemented runtime-checkpoint restore rule or the design
   initial-Agent reset rule is authoritative for a nonpersistent abnormal
   restart.
3. Decide the required failure coupling between Registry, Task Supervisor,
   Runtime Store, Spawn Registry, Agent Servers, and Plugin runtimes. This
   decision must set the Supervisor strategy, exact child order, and whether a
   Plugin runtime pool is separate.
4. Decide one persistence selection and precedence rule. The choices include an
   instance callback, a compile-time adapter declaration, application config,
   and a per-Agent override. The design and current code do not define the same
   rule.
5. Decide whether namespace uniqueness is checked only inside one BEAM node,
   inside one OTP application, or by application policy. Also decide how plain
   `Jido.start_link/1` and `Jido.Default` receive stable namespaces.
6. Decide whether any instance callback is needed now. The seam index calls a
   configuration normalization callback the first useful contract at
   `docs/design/09_jido-instance/README.md:11-14`. The callback document says to
   start with `children/1` at
   `docs/design/09_jido-instance/instance-callbacks.md:30-32` and
   `docs/design/09_jido-instance/instance-callbacks.md:138-140`.
7. If `children/1` is selected, resolve all placement, dependency, purity,
   admission, restore, remote placement, and plain-instance questions listed at
   `docs/design/09_jido-instance/instance-callbacks.md:142-152`.

### Missing verification

1. No canonical test verifies namespace validation, namespace uniqueness,
   namespace-to-local-instance rebinding, or a `Jido.Agent.Ref` facade. The only
   durable rebinding example is skipped. See
   `test/examples/99_research/99_11_stable_reference/stable_reference_test.exs:60-79`.
2. No instance test verifies complete configuration validation before any child
   starts. Current instance tests verify only keyword merge and `max_tasks`
   override behavior at `test/jido/instance_test.exs:95-118`.
3. No test verifies the proposed `:rest_for_one` failure coupling. The
   Supervisor tests check that children exist, but they do not kill Registry or
   Task Supervisor and check later child generations. See
   `test/jido/supervisor_test.exs:4-53`.
4. No test proves that Agent Servers and Plugin runtime hosts use separate
   pools, because the separate Plugin pool does not exist. Current tests prove
   Plugin runtime restart and fresh state, but not pool isolation. See
   `test/jido/agent_server/runtime_lifecycle_test.exs:152-172` and
   `test/jido/agent_server/runtime_lifecycle_test.exs:258-291`.
5. No public contract test compares every generated instance function with the
   proposed facade list, including lookup, timeout, error normalization, and
   wrong-instance Ref rejection.
6. No callback contract test covers callback return validation, callback
   failure containment, child placement, or admission timing. These callbacks
   are not implemented.
7. Persistence tests verify adapter validation and atom-based instance key
   scope, but they do not verify stable string namespace identity or an
   instance-only adapter rule. See `test/jido/persistence_test.exs:35-76` and
   `test/jido/persistence/adapter_test.exs:66-110`.
8. The partition test uses one instance only. Add a canonical two-instance test
   for equal Agent IDs, separate Registries, separate Runtime Store data, and
   separate configured persistence scope. See
   `test/jido/instance_test.exs:206-216`.

## Narrow dependency notes

- Agent identity is a direct dependency. The instance cannot implement a
  Ref-based facade or stable persistence keys until the `Jido.Agent.Ref`
  contract is final. The adjacent identity proposal defines the tuple as
  `{namespace, partition, id}` at `docs/design/03_agent-identity/README.md:10-33`.
- Agent Server is a direct dependency. The instance facade must resolve a Ref
  to the current PID and then call the Server. It must not expose private Server
  state or messages. Current PID functions are listed in
  `lib/jido/agent_server.ex:160-348`.
- Persistence is a direct dependency only for selection, identity, timeout, and
  lifecycle entry points. Adapter storage details are outside this seam. The
  adjacent callback design is explicitly deferred at
  `docs/design/07_persistence/instance-persistence.md:1-14`.
- Plugin lifecycle is a direct dependency only for supervision placement and
  readiness. Plugin behavior stays outside this seam. Current wrappers use the
  Agent Supervisor at `lib/jido/agent_server/plugin_lifecycle.ex:145-155`.
- Observability is a direct dependency only for effective instance config and
  lifecycle observation. Instance callbacks must not replace Telemetry for
  runtime events. See
  `docs/design/09_jido-instance/instance-callbacks.md:108-124`.
- Remote placement and cluster routing are not owned by this seam. The instance
  must define stable identity and local resolution so that another package can
  add location and authority services later.

## Ordered recommendations

The following items are proposals, not current facts.

1. Lock the identity decision first. Define `namespace`, `Jido.Agent.Ref`, plain
   instance behavior, `Jido.Default` behavior, and the PID-to-Ref migration
   period. Do not change durable keys before this contract is final.
2. Lock the restart contract next. Choose the authoritative nonpersistent
   restart rule. Define the required failure coupling and the exact Supervisor
   tree, including separate or shared Plugin runtime supervision.
3. Define one `Jido.Instance.Config` schema and one resolution order. Include
   compile-time declarations, application environment, runtime overrides,
   persistence selection, observability, and timeouts. Validate the complete
   value before `Supervisor.init/2` starts children.
4. Define one persistence selection rule. If persistence is instance-only,
   reject per-Agent adapter overrides. If overrides remain supported, change
   the design text and state their isolation and authority risks.
5. Add the Ref-based instance facade in a compatibility layer. Keep PID return
   and direct Agent Server calls only for an explicit migration period. Give all
   Ref operations one local lookup, timeout, and error-normalization policy.
6. Implement and verify the chosen Supervisor tree. Add failure-injection tests
   for Registry, Task Supervisor, Runtime Store, Spawn Registry, Agent Server,
   and Plugin runtime loss.
7. Defer general instance callbacks until identity, config, supervision, and
   persistence selection are stable. If a concrete service needs instance-owned
   children, implement only `children/1` with a nested Supervisor and a strict
   child-spec return contract. Add `configure/1` or admission only after a
   concrete use case fixes their timing and failure rules.
8. Add contract tests for two-instance isolation, durable namespace rebinding,
   the complete generated facade, wrong-instance Ref rejection, configuration
   validation before child startup, and persistence precedence. Remove the
   skipped durable identity test only after the canonical API passes it.

## Evidence reference summary

- Seam proposal: `docs/design/09_jido-instance/jido-instance.md:1-211`
- Callback proposal and current-state note:
  `docs/design/09_jido-instance/instance-callbacks.md:1-152`
- Canonical instance implementation: `lib/jido.ex:1-741`
- Package Application: `lib/jido/application.ex:1-9`
- Canonical Agent Server startup and PID API:
  `lib/jido/agent_server.ex:85-145`, `lib/jido/agent_server.ex:160-348`
- Canonical Agent Server option and persistence selection:
  `lib/jido/agent_server/options.ex:69-136`,
  `lib/jido/agent_server/options.ex:377-405`
- Canonical Plugin runtime placement:
  `lib/jido/agent_server/plugin_lifecycle.ex:101-226`
- Canonical runtime checkpoint behavior:
  `lib/jido/agent_server/runtime_checkpoint.ex:1-50`,
  `lib/jido/agent_server.ex:2874-2955`
- Canonical persistence identity and adapter selection:
  `lib/jido/persistence.ex:25-57`, `lib/jido/persistence.ex:153-231`
- Main instance verification: `test/jido/instance_test.exs:95-225`
- Current public scope: `guides/core-scope.md:1-22`,
  `guides/runtime.md:1-27`, and `guides/configuration.md:1-106`
