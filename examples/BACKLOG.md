# Jido example backlog

This backlog tracks missing public Jido lessons and required improvements to the
stable example suite. It does not track every public function. A stable example
must teach one distinct contract or lifecycle boundary.

The persistence work in `10_persistence` is active in another work stream.
Coordinate with that work before moving or adding persistence examples.

## Priority

- **P0**: Correct a wrong lesson, an authoring-rule violation, or the catalog.
- **P1**: Close an important public contract gap.
- **P2**: Improve proof depth, placement, or documentation.

## Definition of done

Apply this checklist to every stable example change:

- [ ] The example teaches one main public Jido capability.
- [ ] The source uses public V3 APIs and production-shaped code.
- [ ] Agent, Action, and Flow boundaries have static schemas where applicable.
- [ ] The deterministic path needs no credentials or network service.
- [ ] The test proves the main success case.
- [ ] The test proves one important failure, recovery, or cleanup case.
- [ ] The test uses explicit barriers instead of `Process.sleep/1`.
- [ ] Test-only observers, gates, blockers, and work functions do not enter Turn
      context.
- [ ] The source and test folders have the same numbered path.
- [ ] The numbered README follows the template in [AGENTS.md](AGENTS.md).
- [ ] The section source and test indexes include the example.
- [ ] The focused section test passes with `--include example --seed 0`.
- [ ] `mix test.examples --seed 0` passes when shared support or several sections
      change.

## P0: Correctness and catalog repairs

### Route selection

- [x] Correct `01_06_route_selection` so it does not teach declaration order as
      the main precedence rule.
- [x] Declare a broad wildcard before an exact route and prove that specificity
      still selects the exact route.
- [x] Add an equal-specificity priority case.
- [x] Add a no-match case that returns `Jido.Error.RoutingError`.
- [x] State the complete order: route class, pattern complexity, explicit
      priority, and registration order.

### Test fixture boundaries

- [x] Remove the test-only barrier function from Turn context in
      `04_05_runtime_inspection`.
- [x] Remove observer, gate, and release handles from Turn context in
      `04_13_turn_upgrade`.
- [x] Put fixed barriers in test support and control them outside the example
      Action.

### Public API inventory

- [x] Replace obsolete `Jido.Agent.Directive.Spawn` and `SpawnAgent` entries in
      `mix.exs` with `SpawnProcess` and `SpawnChild`.
- [x] Update [AGENTS.md](AGENTS.md) so stable groups include `09_plugins` and
      `10_persistence`. Prefer wording that does not become stale when another
      stable group is added.
- [ ] Recount stable folders only after the research and persistence moves are
      complete.
- [ ] Update [README.md](README.md) and all section indexes from the folder tree.
- [x] Confirm that only `99_02_distributed_authority` remains in `99_research`.

### Coverage register

- [ ] Add `examples/COVERAGE.md`.
- [ ] Give each public capability one canonical example, when one exists.
- [ ] Record the owner package: `jido`, `jido_action`, `jido_signal`, or
      `jido_ai`.
- [ ] Mark each capability as focused example, combined example, guide-only,
      core-test-only, planned, or out of scope.
- [ ] Link each covered capability to its source and behavior test.
- [ ] Do not use raw example count as the coverage score.

## P1: New stable examples

### `01_07_data_defined_agent`

- [x] Build one neutral Agent with `Jido.Agent.new/1`.
- [x] Construct a live instance with `Jido.Agent.instantiate/2`.
- [x] Show a small validated update with `Jido.Agent.set/2` if it keeps the
      lesson focused.
- [x] Encode and decode the static definition with `Jido.Agent.Codec`.
- [x] Include one Plugin declaration so the Agent round trip also exercises
      `Jido.Plugin.Codec`.
- [x] Use stable identifiers from a trusted `Jido.Codec.Registry`.
- [x] Prove direct and live execution select the same route.
- [x] Reject one malformed or untrusted document.
- [x] State that authoring documents do not contain live identity, state, or
      runtime resources.

### `01_08_custom_signal_selection`

- [x] Implement a custom `handle_signal/2` callback.
- [x] Construct a `Jido.Agent.Turn` explicitly.
- [x] Convert raw Signal data into valid Action input.
- [x] Delegate normal cases to declared routes.
- [x] Prove that the source Signal stays unchanged.
- [x] Prove that explicit rejection does not fall back and does not commit.

### Multi-step Flow Directives

Use the `02_09` slot after the current approval workflow moves to Applications.

- [x] Collect Directives from more than one successful Flow component.
- [x] Prove canonical Directive order.
- [x] Include one successful component that is not part of the final output.
- [x] Prove that a later failure discards the complete Directive batch.
- [x] Prove that live dispatch starts only after the Agent commit.
- [x] Keep detailed Flow execution mechanics in `jido_action` tests.

### Runtime request modes

Assign the final `04_runtime` ID after persistence moves are complete.

- [x] Compare synchronous `call`, best-effort `cast`, and asynchronous
      `send_request` plus `receive_response`.
- [x] Show what result each mode returns.
- [x] Show ordering for several admitted requests.
- [x] Prove that a caller timeout does not cancel work that already started.
- [x] State the overload behavior and delivery limit of each mode.

### Runtime Turn control

- [x] Observe an active Turn through public status data.
- [x] Cancel the matching Turn with `cancel_turn`.
- [x] Reject a stale Turn ID.
- [x] Prove that precommit cancellation preserves the committed snapshot.
- [x] State that cancellation does not reverse completed Action I/O.
- [x] Use a fixed test-support barrier. Do not pass the barrier through Turn
      context.

### Runtime failure policy and Outcome

- [x] Show one precommit failure.
- [x] Show one postcommit notification or Directive failure.
- [x] Inspect the public `Jido.Agent.Turn.Outcome` stage and commit data.
- [x] Show a structured `Jido.Agent.Directive.Error` in its normal workflow.
- [x] Compare one continuing policy and one stopping policy.
- [x] Show one bounded custom or emitted-Signal policy without making a separate
      example for every policy form.

### Heartbeat

- [x] Add one focused `04_runtime` example for `Jido.Plugin.Heartbeat`.
- [x] Show the default heartbeat Signal.
- [x] Show a custom Signal type or interval.
- [x] Reject invalid Plugin options before work starts.
- [x] Prove runtime replacement and owner cleanup.
- [x] Keep clock-sensitive assertions behind explicit synchronization.

### `05_06_orphan_adoption`

- [x] Show the direct child equivalent of `on_parent_exit: :continue`.
- [x] Show the direct child equivalent of `on_parent_exit: :emit_orphan` and
      the orphan Signal.
- [x] Adopt the surviving child through the public adoption contract.
- [x] Prove that the new parent can route work to the adopted child.
- [x] Reject an invalid or duplicate adoption.
- [x] Stop the complete relationship tree during cleanup.

## P1: Rewrites and major refinements

### `04_03_bus_delivery`

- [x] Declare `Jido.Plugin.Bus.Manager` before `Jido.Plugin.Bus.Client`.
- [x] Stop starting the owned Bus directly in the normal behavior test.
- [x] Prove Manager readiness before Client subscription.
- [x] Prove ordered delivery and owner cleanup.
- [x] Keep durable Client recovery behavior in the lesson.

### `04_05_runtime_inspection`

- [x] Keep safe `agent`, `snapshot`, and `status` views.
- [x] Add `plugin_state` and `children` only if the example can stay small.
- [x] Enable and disable the bounded debug buffer with `set_debug`.
- [x] Read bounded events with `recent_events`.
- [x] Prove that secret state is not copied into the user-facing view.
- [x] Keep semantic Telemetry in `04_07_agent_observation`.

### `08_01_audit`

- [x] Replace the custom Audit Plugin with `Jido.Plugin.Audit`.
- [x] Commit one selected domain audit record with domain state.
- [x] Prove that a failed Flow adds no record.
- [x] Prove `max_entries` removes old records.
- [x] Remove the custom live projection from this example.
- [x] Link failed-Turn audit policy to the runtime Outcome example.

### `08_03_inbox`

- [x] Replace the custom single-input runtime with
      `Jido.Plugin.SensorManager`.
- [x] Keep the external-input-to-Signal and duplicate-event lesson.
- [x] Start and stop one tagged sensor.
- [x] Replace the sensor after failure.
- [x] Rebuild the desired sensor set after runtime replacement.
- [x] Prove owner cleanup and stale-revision protection.

### `09_02_runtime_admission`

- [x] Add `validate_options/1`.
- [x] Prove malformed runtime configuration fails before a child starts.
- [x] Prove readiness before admission begins.
- [x] Keep transient runtime input separate from prepared portable input.

### `09_08_commit_projection`

- [x] Rewrite the README with the required headings and corrected grammar.
- [x] Test runtime replacement from the latest committed Plugin state.
- [x] Test hook failure and timeout, or remove unsupported detailed claims from
      the README and link to core tests.
- [x] State clearly that the projection is not a durable event stream.

### Move the approval workflow

- [x] Move `02_09_approval_workflow` to `08_04_approval_workflow`.
- [x] Preserve its multi-Turn application, correlation, and idempotency lesson.
- [x] Remove or test the README claim about untagged Action extras.
- [x] Update previous and next links in Workflow and Applications.

## P2: Advanced authoring examples

These examples are required for complete public ExDoc surface coverage. They
can stay guide-only if extension authors are not part of the stable learning
audience. Record that decision in `COVERAGE.md`.

### Agent authoring extension

- [x] Add a focused example for `Jido.Agent.Extension`.
- [x] Lower one custom static declaration into normal Agent metadata or routes.
- [x] Prove extension order and ownership of foreign entities.
- [x] Reject an unconsumed entity.
- [x] Prove that lowering starts no process and does not bypass validation.

### Topology authoring extension

- [x] Add a focused example for `Jido.Topology.Extension` under `07_topology`.
- [x] Lower one custom static declaration into normal Topology entries.
- [x] Prove that planning starts no process.
- [x] Reject an unconsumed entity.
- [x] Activate the lowered result through the normal Controller path.

## P2: Existing example refinements

### Basic and Workflow

- [x] Refine `01_05_otp_supervision` to define and use an actual `use Jido`
      application module and its facade functions.
- [x] Move the reader-facing runtime Flow and Codec path out of test-only code,
      or document it clearly in `02_01_sequential_flow`.
- [x] Replace the old term “Builder” in `02_01` with “runtime Flow
      constructor.”
- [x] Rename or clarify `02_02_effectful_steps`. It performs synchronous I/O;
      deferred Directives are also called effects in this API.
- [x] Change “shared budget” in `02_08` to “shared continuation limit.”
- [x] Name `Jido.Expr` in the Choice and Iterate READMEs.
- [x] Add one `Jido.Error.code/1` and `to_map/1` assertion to an existing failure
      example. Do not add a separate example only for these helpers.

### Runtime

- [x] Add missing static route schemas in `04_01_scheduled_signals` and
      `04_05_runtime_inspection`.
- [x] Remove the dependency from `04_07_agent_observation` on private support in
      `07_topology`.
- [x] Extend `04_12_stable_reference` with partition isolation.
- [x] Extend `04_12_stable_reference` with `Ref.to_map/1` and `Ref.from_map/1`.
- [x] Add `as: :migrate` to the main route in `04_14_state_migration`.

### Multi-agent

- [x] Add missing static route schemas in `05_02_correlated_requests`,
      `05_03_agent_hierarchy`, `05_04_remote_child`, and
      `05_05_remote_lifecycle`.
- [x] Keep remote-start uncertainty and reconciliation visible in `05_04` and
      `05_05`.

### Topology

- [ ] Add a `max_agents` rejection case to `07_03_bus_swarm`.
- [ ] Add one contributed ownership relation to
      `07_06_plugin_contribution`.
- [ ] Prove one contributed group declaration is applied once for all members.
- [ ] Add a failed activation or degraded repair case to
      `07_07_lifecycle_signals`.
- [ ] Add a static `node:` declaration to `07_08_placement_policy`.
- [ ] Link the peer test from `07_08`, or add an optional peer example that
      proves node and PID replacement.
- [ ] Put `07_09_additive_update` in the `Jido.Examples.Topology` namespace.
- [ ] Add `as:` to its main command route.
- [ ] Prove that removal and changed existing entries are rejected without a
      live change.
- [ ] Confirm Controller and Agent cleanup.

### Applications and Plugins

- [ ] In `08_02_subscription`, use “committed state” instead of “durable state”
      unless the test restores the Agent from external persistence.
- [ ] In `09_03_identity`, state that replay protection lasts for one runtime
      generation.
- [ ] Add a runtime-restart case to `09_03_identity`.
- [ ] Show that admission can consume a nonce even when later route execution
      fails.
- [ ] Bring `07_07`, `07_08`, `09_01`, `09_02`, `09_05`, `09_06`, and `09_08`
      into the required README format.

## Persistence coordination

Do not duplicate work from the active `10_persistence` stream.

- [ ] Decide whether these persistence-first runtime examples move into group
      10: `04_06`, `04_09`, `04_10`, and `04_11`.
- [ ] Keep `04_12_stable_reference`, `04_13_turn_upgrade`, and
      `04_14_state_migration` in Runtime because identity and upgrade behavior
      are their main lessons.
- [ ] Keep `09_07_persisted_state` in Plugins and link to it from group 10.
- [ ] Confirm group 10 covers checkpoint identity, version, portability, and
      state validation.
- [ ] Confirm group 10 covers exact-byte compare-and-swap.
- [ ] Confirm group 10 covers hibernate, thaw, deletion, and tombstones.
- [ ] Confirm group 10 covers `attach`, `detach`, `touch`, and idle
      hibernation.
- [ ] Confirm group 10 covers indeterminate writes and cleanup.
- [ ] Use local deterministic adapters by default. Keep external service checks
      optional.

## Package ownership and suite placement

- [ ] Move `03_llm` to `jido_ai`, or label it as ecosystem integration and
      exclude it from the Jido public-feature count.
- [ ] Track core Flow, Instruction, Action output, Flow extension, Codec
      diagnosis, and step-wise execution in the `jido_action` example suite.
- [ ] Keep only Flow examples here that teach a distinct Agent integration
      contract.
- [ ] Mark `06_factory` as an optional combined application suite. Do not count
      its four fixtures as four new public Jido capabilities.
- [ ] Decide whether `06_factory` belongs in `jido_ai` or `examples/jido_lab`.
- [ ] Mark `08_07_fixed_group` and `08_08_elastic_group` as combined application
      policy, or move them to a demo location.
- [ ] Keep `99_02_distributed_authority` in Research until Jido has a supported
      distributed authority contract.

## Deliberate non-goals

- [ ] Do not add one stable example for every function overload, alias, error
      struct constructor, or utility helper.
- [ ] Do not add one example for every Directive. Show a Directive in the
      workflow that gives it meaning.
- [ ] Keep large malformed-input matrices, bounds, and scheduler interleavings
      in core tests.
- [ ] Keep OpenTelemetry exporter setup and deployment-specific configuration
      in guides.
- [ ] Keep provider-specific persistence checks optional.
- [ ] Do not present application autoscaling or distributed ownership policy as
      a Jido core contract.
