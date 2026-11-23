---
title: Add opt-in native OTP clustering to a Jido instance
type: implementation-plan
status: U1-U3 implemented, U4 deferred
date: 2026-11-23
last-reviewed: 2026-11-23
last_reviewed: 2026-11-23
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Add opt-in native OTP clustering to a Jido instance

## Goal Capsule

Let either of two Fly Machines send work to one durable support ticket. Recover an acknowledged deadline on the other Machine with the same Address and Turn ID.

**Release scope (U1–U3).** Configure one home per Jido v3 instance namespace. The operator must stop the old home and prevent its restart before a move. This is the process fence. This scope can replace the keyed routing and controlled recovery that some applications use from `jido_cluster`.

**Evidence gate (U4).** Put the only write authority on B and test automatic A-to-B takeover. Two workers can live through a partition. Only the current grant can authorize a durable write. U4 needs separate release approval.

## Product Contract

### Requirements

| ID | Contract |
| --- | --- |
| R1 | Opt in per instance. One home serves its entire namespace. Preserve the local default. |
| R2 | Route a supported Address operation once. Both ingress nodes can open a pre-created ticket and later read its result. A lost reply can leave the outcome unknown. |
| R3 | Recover a saved Turn after a verified move. Its deadline must commit one escalation in Agent state without a new request. |
| R4 | Prove routing, crash, partition, rejoin and move with focused unit tests and runnable multi-node examples. Prove automatic takeover separately before offering it. |
| R5 | Add zero package dependencies to production or tests. Use OTP distribution, `:erpc`, `:peer` and Mnesia for the required profiles. Maintain one v3 instance implementation. |

### Two-node operating contract

A starts as home. B accepts ingress and holds the only disk copy in the durable profile. The deployment controls which release can start a home.

| Event | Fixed home in the proposed release | One-way takeover if U4 passes |
| --- | --- | --- |
| A and B are connected | Both route to A. Its local Registry admits one managed activation per Address. | B authorizes A. Both route to the granted owner. |
| A crashes | B waits for proof that A cannot restart as home. The operator can then move the namespace to B. | B can replace A's grant and restore the ticket without an operator. |
| The link fails while both live | B stays ingress. A retains its role. With the table on B, A cannot confirm a new durable write during isolation. A home-local store has different availability. | B may promote itself under the same policy as for an A crash. A can keep running old work. B rejects writes under the old grant. |
| B or its disk is unavailable | The ticket cannot make durable progress until the canonical store returns. | New authoritative work stops. A cannot take over from B. Loss of the only disk is outside recovery. |
| The link returns | With no move, restore store access before opening the route to A. After a move, A can return only as ingress for B. | Read B's durable decision. Retire stale workers and timers. B remains owner after promotion. |

A node-down event cannot distinguish a crash from a live partition. If both isolated nodes promote themselves, both can accept work for the same Address. The cost of one-way takeover is dependence on B. Clock skew, operator delay and storage recovery preclude a maximum deadline latency.

### Compatibility and scope

Keep the existing `{namespace, partition, id}` Address and v3 record formats. The new call and instance options are additive. Other instances and standalone AgentServers keep their current behavior. Per-key placement, balancing and automatic failback stay outside the release. An application that requires unattended takeover must retain its existing path until U4 passes and is approved.

## Planning Contract

### Current system

Jido `b9dd510a` is v3.0.0-beta.3. The alpha legacy package at `1bae878` declares Jido `~> 2.4`. [Jido project](../../mix.exs) · [Legacy source](https://github.com/agentjido/jido_cluster/tree/1bae8783128e8cc549ec266402e6563a08639258) · [Chapter 26](../../examples/26_distributed_agents/README.md)

- `Jido.start_link/1` claims the local namespace. `init/1` binds it, opens the manifest and stores instance defaults. The `:one_for_one` tree starts Wake before the Agent DynamicSupervisor. Startup then waits for Wake. Option validation can open a store even in `child_spec/1`. A generated instance can also evaluate its module persistence default during option construction. [Instance](../../lib/jido.ex) · [Options](../../lib/jido/instance/options.ex) · [Persistence config](../../lib/jido/persistence/config.ex)
- The Registry points to a local activation root. Address calls can restore an existing record. A missing record needs explicit creation. `Jido.AgentServer.child_spec/1` can start a registered activation under another supervisor. `Worker.start/1`, `Worker.start_link/1` and the activation supervisor use `Worker.activation_options/1`. Local parent-child ownership expires with the activation. [AgentServer](../../lib/jido/agent_server.ex) · [Activation supervisor](../../lib/jido/agent_server/supervisor.ex) · [Worker](../../lib/jido/agent_server/worker.ex) · [Local ownership](../../lib/jido/agent_ownership.ex)
- The worker registers the wake before saving the wait and replying `:waiting`. WakeStore writes shards and a separate index. The Flow also stores execution events and facts. Wake makes a synchronous Address call and currently accepts any returned `TurnResult` as delivery. A second timed wait can call back into Wake. [Wake](../../lib/jido/instance/wake.ex) · [WakeStore](../../lib/jido/persistence/wake_store.ex) · [ContinuationStore](../../lib/jido/persistence/continuation_store.ex)
- Chapter 26 uses an application RPC wrapper in 26_01, a shared test directory in 26_02 and two RAM copies in 26_03. In 26_04 the test kills A and explicitly starts B. In 26_05 both workers survive reconnect. The last two examples default to SQLite and can use PostgreSQL. Keep these cases as controls. [Chapter tests and operating limits](../../examples/26_distributed_agents/README.md)

### U1. Route and admit work at the fixed home

Use one runtime option with `cluster: false` as the default. This proposed configuration applies to the generated instance or to `Jido.start_link/1` with `name: MyApp.Tickets`.

```elixir
config :my_app, MyApp.Tickets,
  namespace: "support/tickets",
  cluster: [home: :"tickets@a-id.vm.my-app.internal", generation: "move-1", rpc_timeout: 5_000],
  persistence: {Jido.Persistence.Mnesia, table: :ticket_records, sync_writes: true}
```

Set the same instance name, namespace and home on both Machines. Require a named BEAM, a trusted home node atom and a finite positive RPC timeout (default 5,000 ms). Require a nonempty generation string for a durable home. Reject missing namespace, invalid values, unknown keys and duplicates.

**Startup.** Select the role before adapter I/O in both generated options and `child_spec/1`. Ingress needs only its local namespace binding and role data. It can boot with the home and store offline. It starts no Agent subtree or Wake. A durable home must match a separately provisioned `{home, generation}` record before opening the manifest. Start the Agent supervisor and its dependencies before enabling overdue wakes. Open external admission after Wake recovers. Internal wake delivery must work during startup.

Store the role and current instance generation under the supervisor. Close admission on missing role data, dependency failure or shutdown. Release the namespace after failed startup. A permanent child can restart after `Jido.stop/1`. Control its parent during a move. [RuntimeStore](../../lib/jido/instance/runtime_store.ex) · [Instance supervision](../../lib/jido.ex)

**Routing.** Route `Jido.call/4`, `cast/3`, `status/3` and `turn_result/3`. Ingress uses one `:erpc.call/5` to a fixed internal function. Carry the expected home and deployment generation in the request. The receiver checks both, the protocol, operation, instance, namespace and readiness. It validates portable inputs and calls only the local implementation. Return process-neutral results. Caller mailbox deliveries and PID handles have local scope. [OTP erpc](https://www.erlang.org/docs/27/apps/kernel/erpc.html)

**Ticket open.** Provision the record on the home. Save the product's Turn ID before sending the Signal. Current `call/4` generates an ID and cannot request retention. Add `Jido.call(instance, address, signal, turn_id: id, result_handoff: true)`. Use the same retained form on a local durable instance. The home calls `submit` and `await` in one process and returns the waiting or terminal result. On timeout abandon only the pending reply. Use `turn_result/3` from either node. `:not_found` can mean the Turn is still running. Record the terminal result, then acknowledge it on the home to unblock later Turns. Reusing an ID does not deduplicate submissions. [Worker call and submit](../../lib/jido/agent_server/worker.ex) · [Ticket example](../../examples/26_distributed_agents/support/ticket.ex)

**Timeouts and results.** Cap the remote reply wait by both `rpc_timeout` and the caller's wait. Cap `:infinity` too. Send durations and construct deadlines on the home monotonic clock. Account for local resolution and queue time. Keep RPC wait, admission timeout and Turn timeout separate from the saved wall-clock deadline. A timeout cannot cancel accepted work. Distribution can delay timeout reporting. [AgentServer lifecycle](../../lib/jido/agent_server/lifecycle.ex) · [OTP erpc](https://www.erlang.org/docs/27/apps/kernel/erpc.html)

| Observation | Public result for a clustered Address |
| --- | --- |
| Invalid input, explicit admission rejection, or completed Turn | Preserve the Jido error or exact `TurnResult`, including `:uncertain`. Cast `:ok` means the home issued a best-effort cast. |
| Endpoint proves it rejected the target before dispatch, or a read RPC fails | Return `{:error, :cluster_unavailable}` for availability failures. Preserve authoritative read results, including `{:error, :not_found}`. |
| A mutating RPC times out, loses the link, or loses its worker after dispatch could have started | Return `{:error, {:cluster_outcome_unknown, reason}}`. Classify failure at the worker call. `with_address_server` currently collapses some post-dispatch exits into `:unavailable`. Distinguish a missing dispatch endpoint from an exception inside an accepted call. Reconcile from the saved state. Make no automatic replay. |

**Local API boundaries**

- Ingress returns `{:error, :cluster_not_home}` for create, activate, start, thaw, reconcile, upgrade, replace, delete, `stop_agent`, cancel, submit, ownership transfer and result acknowledgement. `Jido.stop/1` stops the local instance. A valid local-only lookup returns `{:error, :not_found}` from `resolve_agent/2`. The corresponding `whereis_agent`, list and count return `nil`, `[]` and `0`.
- Guard instance-selected Persistence reads and writes. Require a runtime store declaration for this profile. Reject a conflicting compiled store default before adapter I/O. Missing instance state must never enable offline module fallback.
- Admit only activations owned by the home supervision tree. Reject external `child_spec/1` and bare-worker starts with `jido:`. Check supervision ancestry and generation at registration and on child restart. Apply worker admission to cached PIDs, casts and postponed work during drain. Explicit raw store access and unmanaged software are outside the guarantee.

U1 owns `Jido`, `Instance.Options`, `Instance.RuntimeStore`, one internal dispatch module and guards at activation, worker admission and persistence resolution. Include the home-record check and one offline CAS command in U1. Calls to different Agents can run concurrently. [Instance API](../../lib/jido.ex) · [Persistence resolution](../../lib/jido/persistence.ex)

### U2. Recover the same deadline after a verified move

**Storage on two Fly Machines.** Include the OTP `:mnesia` application in the host release. Set B's Mnesia directory on its mounted volume. Create its disk schema once while Mnesia is stopped. Start Mnesia and create a `:set` table with `[:key, :value]`, `disc_copies: [node_b]` and `local_content: false`. On A, use `schema_location: :ram` and `:mnesia.change_config(:extra_db_nodes, [node_b])`. Check that B alone holds a table copy before opening the namespace. A Fly volume attaches to one Machine. Separate volumes require explicit replication. [Mnesia](https://www.erlang.org/docs/27/apps/mnesia/mnesia.html) · [Fly Volumes](https://docs.fly.io/volumes/overview)

The current adapter accepts only `table:` and uses `:mnesia.transaction/1`. Add the proposed `sync_writes: true` option for this profile. Use `:mnesia.sync_transaction` for puts, compare-and-swap (CAS) and deletes. It waits for B to commit and log the write. Keep the current default for existing users. Kill A immediately after the waiting reply. A read barrier on B could conceal an early acknowledgement. Disk destruction and storage rollback exceed this contract. [Mnesia adapter](../../lib/jido/persistence/mnesia.ex) · [OTP transaction semantics](https://www.erlang.org/docs/27/apps/mnesia/mnesia_chap4.html)

Two-peer probes on OTP 27 and 29 confirmed that isolation blocked writes from A. Restarting A's RAM client restored access. A synchronous value survived A's immediate OS kill and B's subsequent orderly Mnesia restart. The ticket test below must verify the same boundary through Jido.

**Deployment and move procedure.**

1. Install compatible releases on both Machines before enabling the namespace. Use distinct long node names, a shared secret cookie and `-proto_dist inet6_tcp` on the private network. Pin each hostname to its Machine, for example `<machine_id>.vm.<app>.internal`. Permit EPMD and the configured distribution port between those peers. Connect with `Node.connect/1`. Keep B and the deadline home running when HTTP is idle. Block old binaries, unclustered instances and maintenance writers from opening this namespace outside the move procedure. [Fly private networking](https://docs.fly.io/networking/private-networking) · [OTP distribution options](https://www.erlang.org/docs/27/apps/erts/erl_cmd.html)
2. Provision one separate home record for the namespace in the canonical store. It contains the allowed home and the release generation. Apply the offline CAS to a separate key in that namespace. Use `:not_found` only for initial provisioning. Check it on every opted-in durable home start. Reject a missing, stale or unreadable record. Only offline provisioning of a verified new namespace can create it. A restarted release must use the existing record. The stop procedure fences work admitted earlier.
3. Close new work and pause new wake deliveries. Keep wake registration available while admitted work settles. Stop the complete old home tree. For a crash, verify the old Machine has stopped through the host control plane. Block old release restarts, autostarts and replacement jobs throughout the move. Keep B in ingress mode if a writer, startup attempt or store decision remains unaccounted for. A node-down event cannot authorize this step. [Fly Machine restart policy](https://docs.fly.io/machines/guides-examples/machine-restart-policy)
4. On B, resolve interrupted transactions. Verify the manifest, Agent revision, Flow checkpoint and indexed wake against the last acknowledged wait. If a result already exists, keep it. CAS the old home record to `{B, new_generation}`. Read it back after an uncertain response. Replace B's ingress child specification with the new home configuration. Recalling `Jido.start/1` cannot reconfigure a live instance. Keep B's store running.
5. Wake reloads the index and restores a due Turn through its Address. Match the saved Turn, wait and absolute deadline. Remove the occurrence only after a durable result or authoritative evidence that it is obsolete. Reconcile an uncertain write or missing dependency before cleanup. Dispatch due work in bounded, monitored tasks under the home. This leaves Wake free to register another timed wait. Stop or invalidate old tasks on Wake restart. Open external ingress after recovery is ready.
6. Return A as ingress with the new configuration. If A is still home after a link cut, restart its RAM-only Mnesia client and join B's verified schema. Keep the disk node name and volume identity stable across Machine replacement. Keep service closed on an `inconsistent_database` event until the operator verifies the authoritative data. `Node.connect/1` and `wait_for_tables` establish reachability and table availability only. Roll back by fencing B and moving forward from its latest data and a fresh generation. [Mnesia partition recovery](https://www.erlang.org/docs/27/apps/mnesia/mnesia_chap7.html)

U2 changes the Mnesia adapter and the Wake delivery path. A deadline commits one escalation in Jido. For an external ticket update, persist an intent keyed by Address, Turn or occurrence, and effect kind. Require the destination to deduplicate it or enforce a fencing token. Otherwise reconcile before resending. [Recoverable external delivery](../../examples/24_application_patterns/24_07_recoverable_external_delivery/README.md)

### U3. Migrate the supported legacy use case

| Legacy contract | Migration |
| --- | --- |
| `Jido.Cluster.InstanceManager` / `JidoCluster.InstanceManager` keyed calls | Map the manager to a namespace. Encode each legacy key as a stable, collision-free Address ID. Create the v3 record first. `get` used to get or start a PID. Route by Address and use `status/3` for observation. Use home-local lifecycle operations. |
| Replicated casts, standby processes, rendezvous placement, rebalancing, `owner_node` and `stats` | A v3 cast gives best-effort dispatch. Consumers that require standby acknowledgement, live placement or management APIs need v2 or an accepted replacement. |
| Cluster adapters, leases, partition freeze, disconnected islands and discovery | Leave ETS/Mnesia/Bedrock/PostgreSQL **legacy cluster adapters** and their data model on v2. The release uses v3 Persistence and deployment-owned connections. |

Only the legacy package appeared in the workspace Mix declarations and locks. Inventory deployed and external consumers. Publish a migration guide with the U1–U2 commands and a worked key mapping. Rehearse v2 export and v3 import on a copy. Verify identity, state, waits and results. Quiesce and fence the v2 writer before final export or cutover. A pending workflow without a verified translation stays on v2. Release core first, then migrate consumers. Retire v2 only when each affected owner has a tested replacement or an accepted maintenance path. Archiving needs separate approval and a workspace-map update.

### U4. Prove one-way automatic takeover

Keep B as the **only authority and data holder**. At a fenced offline cutover, retire the fixed-mode home record and A's direct Mnesia access. Require both candidates to use one grant-bound Store profile. A stale fixed-home configuration must fail its boot check. Only B's supervised controller executes protected transactions, synchronously against its local table. Keep A outside B's Mnesia schema in this profile. User code runs outside the controller.

1. Provision A as initial owner once. B persists the owner, its session identity and a grant number that only increases (the epoch). Bind a session to a BEAM incarnation and an instance/controller generation. Arm takeover after A first becomes ready. A monitor loss or timeout can trigger B's conditional `A → B` update. Compare the exact prior grant under a write lock. Start B only after commit or read-back of the exact new grant. A stale startup cannot change the direction.
2. Resolve the current owner at B and dispatch the Signal at most once with that grant. Check it online at activation, worker admission (including dequeue) and wake dispatch. Admission takes effect at B's check. Cover stale PIDs, casts, postponed Turns, timer callbacks and enabled topology or Plugin admissions. Reject unsupported paths at startup. Read authoritative status and results through the current grant. An old PID can supply local diagnostics. An earlier admission can still execute after the epoch changes. Never refresh an old task's grant to finish it under a new owner.
3. On B, compare the **captured grant and the data condition in the same synchronous transaction** as each protected mutation. Include manifest creation, Agent and result CAS, acknowledgement, tombstones, execution facts, log batches, read repair, garbage collection, wake index/shard updates and delayed cleanup. Keep the grant in managed runtime and store context. A separate grant check followed by adapter CAS permits a stale write. The adapter rejects nested transactions. Return `{:error, {:rejected, :stale_grant}}` for a verified refusal. Read back an indeterminate write from B. Reject memory-only Agents and any writer that cannot use the protected store in this profile. [Byte store](../../lib/jido/persistence/store.ex) · [Continuation writes and cleanup](../../lib/jido/persistence/continuation_store.ex)
4. Start controllers closed. Stop the owner's Workers, tasks and Wake as a group on controller loss. Ordinary `:one_for_one` siblings can survive. A replacement B controller resolves pending transactions on the same disk. It preserves the durable owner and advances the epoch under the same lock before serving. Rebind only a fresh owner session. A reused node or process name supplies no grant. Reject old queued RPCs and timers. Missing or rolled-back authority data requires offline recovery with all prior sessions fenced.
5. Restore B after its grant commits. A can learn of the change late. A delayed reply for a commit accepted before promotion remains valid. On rejoin, retire A's old workers and timers. B stays owner. Exclusive live activation requires positive process fencing, as in U2.

Scoped `:pg` can advertise ready PIDs. Its membership is eventually consistent, covers direct connections and can disappear on scope restart. `:global` and node monitors also describe the visible network. OTP distributed applications place a whole application. None supplies a per-instance grant atomic with Jido writes. Leave them out of the fixed route. [OTP pg](https://www.erlang.org/docs/27/apps/kernel/pg.html) · [OTP global](https://www.erlang.org/docs/27/apps/kernel/global.html) · [OTP distributed applications](https://www.erlang.org/docs/27/system/distributed_applications.html)

If both Agent hosts must be replaceable, a third node can own the grant and canonical data. Its loss then stops both hosts. Continued service through loss of any one of three nodes is a separate requirement. With two table replicas, `majority: true` requires both for a transactional update. Without a majority check, two live partitions can diverge. A third fixed durable replica could permit a two-of-three **transactional update**. Reads, dirty operations, a witness heartbeat and node counts cannot establish that permission. Require aligned grant/data replicas, guarded writes, normal OTP partition protection and tested recovery from stale replicas. Keep suspect replicas offline. Never force-load them or lower the majority during an outage. [Mnesia table options](https://www.erlang.org/docs/27/apps/mnesia/mnesia.html) · [Mnesia recovery](https://www.erlang.org/docs/27/apps/mnesia/mnesia_chap7.html)

### Verification contract

Add two runnable examples after 26_05. Each needs a public-API example, a README command and a colocated `*_test.exs` with `@moduletag :integration`. Reuse the chapter's ticket and peer support. Each native case runs independently of the SQL controls. Use `:peer` with `connection: :standard_io`. Keep the ExUnit origin outside routing, ownership and storage. [PeerCase](../../test/support/jido_agent_server/peer_case.ex) · [Peer hosts](../../examples/26_distributed_agents/support/peer_hosts.exs) · [OTP peer](https://www.erlang.org/docs/27/apps/stdlib/peer.html)

Isolate peer names, cookies, schemas and temporary directories. Install gates before work starts. Disable automatic reconnect in both directions during a cut. Confirm each live peer's view through its control connection. Use bounded telemetry, monitor or result observations. Restore links and stop peers on every exit path.

| Example and precondition | Fault or action | Observable pass condition |
| --- | --- | --- |
| **26_06 native fixed home.** Both instances ready. Same dormant, pre-created Address. A separate local instance uses the same ID. | Release A and B callers together. Race direct activation and an externally supervised child on B. Send a cast. | Both calls report one activation ID and Agent revisions 1 and 2. B has zero residents and rejects the direct starts. The cast is visible at A. The local instance retains its own state. |
| **26_06 routing errors.** A uses a home-local store. | Run independent faults from a ready baseline. Stop the target instance on a connected A. Cut the live link before a call, then in a separate run after a Turn-start gate. Force a reply timeout with the link up. Release accepted work. | The verified rejection returns unavailable. The ambiguous mutations return unknown. During the cut B cannot activate and A can commit locally. After reconnect, the accepted change appears once on the same home. No replay or promotion occurs. |
| **26_07 native ticket recovery, orderly move.** A holds a waiting approval. The native table and home record are on B. | Withhold the operator fence. Keep the old home record and try to start B as home. Then close A, confirm all producers stopped, change the record, and restart both with the new configuration. Try A's stale configuration too. | Premature and stale starts fail before manifest or wake writes. B restores the same Address and Turn with a new activation. A routes to B. Only B can complete the approval. |
| **26_07, hard crash.** B opens a pre-created ticket through its public Address call with a known Turn ID. Install a gate that holds A's deadline resume before its first durable mutation. | On `status: :waiting, durability: :durable`, kill A immediately through its OS PID. Confirm exit independently. Inspect the canonical wait on B **after** the kill. Hold B's home closed until its clock reaches the saved deadline. Perform the verified move. | With no test activation, wake or repeat open, B records one escalation on the original Turn. Read the same retained result twice. Repeat the captured occurrence before and after acknowledgement. Check that it adds no Agent revision. Verify lookup then returns `:not_found`. Approve a second ticket early. Its due occurrence leaves it approved. |
| **26_07, store partition.** Only B holds the table. Both Machines live. | Cut A–B during a gated write. Attempt a fresh write on isolated A. Rejoin its RAM client from B and read the authoritative state. | A cannot confirm the fresh durable write. B makes no automatic move. Reconcile the in-flight write from B. Routing resumes only after a verified rejoin. An unavailable or inconsistent store keeps recovery closed. |
| **26_08, U4 evidence only.** Both candidates running. A has a grant and one acknowledged deadline. Hold a separate A write at B's RPC receiver before it enters the controller. | Cut A–B while A stays alive. Let B automatically take over. Present the captured A write to B after the change with its data revision still current. Also exercise an old PID, a postponed request and stale wake cleanup. Repeat with A killed. | B admits and completes the saved deadline without operator action. The old epoch cannot admit, commit or delete a required wake. Exercise both stale mutations at B before retiring A. Observe A's live worker after promotion. After reconnect no old work succeeds and B stays owner. |
| **26_08, controller failure.** A queued write holds the old session. | Kill the owner controller while its BEAM lives. Kill B's authority controller before and after a grant commit, drop the reply and restart from the same disk. Stop B entirely in a separate run. | Closed gates survive sibling restarts. Ambiguous claims require read-back. Epochs advance across restart. Delayed writes, former controller sessions and stale A configuration are refused. No candidate admits new authoritative work while B is unavailable. |

**Focused unit tests**

- Instance and AgentServer cover option validation, local defaults, direct and generated startup, ingress boot without storage, rollback and role mismatches. Exercise every U1 bypass, finite and infinite waits, admission expiry and forwarding-loop refusal.
- Persistence and Wake inject failure between the shard, index and saved wait, and between terminal commit and cleanup. An incomplete wait receives no durable acknowledgement. A matching terminal result permits cleanup. A transient failure keeps the entry. Test an overdue wake at boot, a restarted Wake and a Flow that registers a second wait during delivery.
- For U4, race claims and boot both candidates with one overdue wake. Require one grant and one effective delivery. Verify stale puts, CAS, deletes, repair and cleanup fail with otherwise valid data conditions. [Instance tests](../../test/jido/instance) · [Wake tests](../../test/jido/instance/wake_test.exs) · [Mnesia tests](../../test/jido/persistence/mnesia_test.exs)

Run these commands from the Jido repository during implementation. Run each new example alone, then run the complete examples alias to check discovery and regression behavior.

```sh
mix test test/jido/instance test/jido/persistence/mnesia_test.exs --warnings-as-errors
mix test test/jido/agent_server/durable_turn test/jido/agent_server/core test/jido/durable/continuation_test.exs
mix test.examples examples/26_distributed_agents/26_06_native_fixed_home --warnings-as-errors
mix test.examples examples/26_distributed_agents/26_07_native_ticket_recovery --warnings-as-errors
mix test.examples examples/26_distributed_agents --warnings-as-errors
mix test.examples
mix test.peer
mix test.load
mix test.contracts
mix reach.check --arch --smells
mix format --check-formatted
mix test.ci
```

For the U4 decision, require `mix test.examples examples/26_distributed_agents/26_08_one_way_takeover --warnings-as-errors` on the same profiles. Update the component obligations, ADR index and dependency map during implementation. [Mix aliases](../../mix.exs) · [OTP minimum](../../CONTRIBUTING.md) · [Instance Covenant](../../test/contracts/jido/instance.obligations.md) · [ADR index](../adr/README.md) · [Dependency map](../architecture/module-dependency-map.md)

### Release decisions and definition of done

- **Core maintainer.** Confirm the offline home record and retained Address call. Implement U1 routing, then U2 recovery and U3 migration. Release them together when the native examples pass. Local regression tests and the pre-existing example controls must also pass.
- **Application operator.** Accept B as the disk dependency. Demonstrate restart control, stale-home refusal and recovery on the intended Fly deployment. Record unavailable and unknown outcomes, role, generation, Turn ID and recovery time without recording ticket payloads or cookies.
- **Automatic takeover.** Run U4 only for a product that needs unattended A-to-B recovery and accepts one authorized writer with possible process overlap. Release it only after the two-peer tests pass and the maintainer accepts the extra fenced write surface. If any required mutation escapes the grant, keep the fixed-home release scope. An application that needs service through loss of B needs a different storage and authority decision.

## Adapter Results

The fixed-home and native ticket recovery examples pass on OTP 29. The full offline example suite and `mix ci` pass on OTP 29. U4 remains deferred. The Fly deployment drill remains required before production use.
