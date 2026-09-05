> Historical donor review. Results and diagnostic scripts apply to the source
> named here. They are not current core acceptance evidence. See
> [core validation](../../migration/10-execution-record.md).

**Jido v3 SDK survey — 2026-09-04**

Jido has a sound local Actor model and useful remote child ownership. I would continue with this design. I would fix remote admission deadlines before using it for general coordination across Erlang nodes. Cluster ownership, work recovery, and load control also need explicit contracts.

All 43 active catalog fixtures passed their current tests. The complete suite passed 878 of 881 tests. Separate diagnostics found two remote API defects and reproduced the hibernate/thaw race. The group failures have both test setup faults and unresolved recovery behavior.

I reviewed the working copy at commit `bd05a32869c3fadcd82a6bc636c154fb69f434d4`. Git reports branch `main`. There were 266 existing changed or untracked entries before this review. Thus, these results describe the experimental working copy, not the commit alone. The host uses Elixir 1.20.3 and OTP 29.0.5. I did not test the Elixir 1.18 / OTP 27 baseline, a multi-host network, or a live provider. I made no SDK changes. The new files contain this report, diagnostics, and evidence.

**Execution results are reproducible.**

| Check | Result | Evidence |
| --- | --- | --- |
| `mix examples --seed 0 --trace` | 170 passed; 711 excluded; 10.6 seconds | [Example log](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/docs/reviews/2026-09-04-sdk-survey/evidence/examples.log) |
| `mix test --include example --include integration --include flaky --seed 0 --trace` | 878 passed; three failed; all 881 tests ran; 45.3 seconds | [Full log](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/docs/reviews/2026-09-04-sdk-survey/evidence/full.log) |
| `mix quality` | Format, compile, Credo, and Dialyzer passed | [Quality log](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/docs/reviews/2026-09-04-sdk-survey/evidence/quality.log) |
| `mix docs --no-open` | Passed | [Docs log](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/docs/reviews/2026-09-04-sdk-survey/evidence/docs.log) |
| Remote Child demo | Remote command, child placement, and child stop passed | [Remote demo log](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/docs/reviews/2026-09-04-sdk-survey/evidence/demo-remote.log) |
| Actor Observation demo | Both expected terminal outcomes were observed | [Observation log](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/docs/reviews/2026-09-04-sdk-survey/evidence/demo-observation.log) |
| Recoverable Delivery demo | Restored intent completed; the sink retained one record | [Delivery log](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/docs/reviews/2026-09-04-sdk-survey/evidence/demo-delivery.log) |
| Recursive Analysis stress runner | 12 validated runs; 100,000 records per run; four Actors; three rounds | [Stress log](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/docs/reviews/2026-09-04-sdk-survey/evidence/stress.log) |
| Local fleet diagnostic | 1,500 Actors, 1,500 commits, zero remaining Actors or owned tasks | [Fleet log](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/docs/reviews/2026-09-04-sdk-survey/evidence/fleet.log) |

The catalog has 254 acceptance tests: Basic 22, Workflow 35, LLM 66, Runtime 93, and Multi-agent 38. All passed. Of these, 84 are core tests outside `test/examples`. The [complete matrix](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/docs/reviews/2026-09-04-sdk-survey/example-matrix.md) lists every fixture and its test files. The test logs contain some Elixir 1.20 type warnings in deliberate invalid-input tests. They are not the cause of the failures. I did not run the coverage gate.

The research queue has one passing and one failing DIST-03 test. Its four other items are plans without executable tests. The 48 removed application fixtures remain archive material. I did not count them as working examples.

**Fix the remote deadline defect first. Priority: P1.**

[Server.call/3](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/lib/jido/actor/server.ex:191) builds an admission deadline from the caller VM's monotonic clock. [Server admission](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/lib/jido/actor/server.ex:682) compares it with the destination VM's clock. [The clock helpers](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/lib/jido/actor/server.ex:2585) have no node conversion.

The diagnostic starts two real VMs about six seconds apart. Their sampled monotonic clocks differ by 6,572 ms. A local command succeeds. The same generated command from the younger VM to the older VM returns `{:error, :admission_timeout}` with the default 5,000 ms timeout. The destination Actor is idle.

The reverse direction is also wrong. I suspended the destination Server, sent a remote command with a 100 ms timeout, and waited for that call to time out. After I resumed the Server, the command executed and committed revision 1. It had not started execution before the caller timeout. A same-node control rejected the expired command and preserved the state. This differs from the documented rule that already-started work may continue after caller timeout.

Run [remote_api_probe.exs](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/docs/reviews/2026-09-04-sdk-survey/remote_api_probe.exs) to reproduce both cases. See the [default-timeout evidence](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/docs/reviews/2026-09-04-sdk-survey/evidence/remote-api-default.log). The existing two-node tests start peers close together and use larger timeouts. They therefore miss this condition.

Use node-local clocks for elapsed time. Define the remote admission budget, its start point, and how to revoke pending work. Keep caller wait, queue admission, and execution limits separate. Do not replace this with a wall-clock deadline without a clock-error policy. Add tests with staggered VM starts, both call directions, remote queue delay, `send_request`, and `:infinity`. Erlang documents monotonic time as a clock supplied by each runtime with an unspecified origin. [Erlang time guide](https://www.erlang.org/doc/apps/erts/time_correction.html).

**Cluster identity still has no exclusive owner. Priority: P1 for automatic failover.**

The [enabled DIST-03 assertion](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/test/jido/actor/distributed_authority_test.exs:32) expects a second start to return the first owner. It instead gets another live PID on the second node. The companion test passes: a replacement restores revision 1, commits revision 2, and blocks a stale write from the old activation.

That is useful storage protection. It does not stop both activations from doing external work before a commit. The shared ETS test store also depends on its owner VM. It proves the comparison rule, not storage survival after that VM is lost.

I recommend a small optional ownership-provider contract. Keep node-local supervision in core. Give the provider claim, renewal, release, and authority-loss operations. Keep logical Actor ID, activation ID, owner token, and checkpoint revision separate. Check the owner token at storage and effect boundaries that require exclusive authority. Define what happens when renewal cannot be confirmed.

A local mode should remain simple. A distributed mode should declare its partition policy. Membership and placement can use BEAM facilities, but they do not establish permission to write. The Erlang `global` API provides names and locks over participating nodes; its network assumptions still matter. [Erlang global documentation](https://www.erlang.org/doc/apps/kernel/global.html). My recommendation is to make authority an explicit extension boundary before adding singleton or shard claims to the SDK.

**The public liveness helper fails for remote PIDs. Priority: P2.**

[Server.alive?/1](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/lib/jido/actor/server.ex:287) calls `Process.alive?/1` directly. The diagnostic returns `true` for a local live PID and raises `:badarg` for the same live PID from another node. Other Server operations accept remote PIDs.

Make the public contract consistent. If a remote check is supported, use a bounded query and document its result during loss of connection. A separate reachability result can distinguish known exit from unavailable evidence. The private child-placement code already has a remote check, but that does not repair this public function. This defect is reproduced by the same remote API probe.

**Hibernate returns before immediate thaw is safe. Priority: P2.**

The full run passed this test. A focused `--repeat-until-failure 30` run failed on its first iteration. [The existing assertion](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/test/jido/instance_test.exs:140) receives `:ok` from hibernate, then `{:error, {:already_started, pid}}` from thaw. See the [focused log](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/docs/reviews/2026-09-04-sdk-survey/evidence/hibernate-repeat.log).

[The idle hibernate handler](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/lib/jido/actor/server.ex:521) uses `stop_and_reply`. [The public wrapper](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/lib/jido/actor/server.ex:355) does not wait for termination or registration removal. Give successful hibernation a complete stop boundary before the caller can reuse the identity. Preserve the test. Do not repair the example with an arbitrary delay.

**Fixed Group fails in two stages. Priority: P2.**

The original [scenario](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/test/integration/fixed_group/fixed_group_test.exs:12) times out at its readiness replay assertion on line 38. Its Bus uses global scope. [Directive dispatch](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/lib/jido/actor/server/directive_runtime.ex:502) uses the Actor's Jido instance. The diagnostic finds a global Bus, no instance-scoped Bus, and no replay records. The controller nevertheless knows that four children started.

I then corrected only Bus startup and input lookup in diagnostic copies. The scenario reached the restart assertion. It expected `["task-8"]`; the restarted worker contained `["task-2", "task-5", "task-8"]`. Current SDK restart behavior correctly retains committed state. Decide whether this example needs restoration or a new worker lifetime, then align the assertion with that policy.

**Elastic Group loses work after worker restart. Priority: P1 for recoverable groups.**

The original [scenario](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/test/integration/elastic_group/elastic_group_test.exs:12) times out at line 78. Its first failure also comes from the Bus scope mismatch. At failure, the controller has ten assignments and three queued jobs. All workers remain ready with empty task state. Work never reached them.

After the same scope correction in diagnostic copies, 12 of 13 jobs complete. Worker 1 restarts with `phase: :busy` and its old `elastic-task-1`. Its one-shot completion timer is gone. [Work admission](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/test/integration/elastic_group/example_test.exs:75) rejects new work unless the phase is ready. The controller's retry therefore cannot finish.

Persist the work intent and attempt identity. Reconcile that intent when the worker starts. Choose retry, cancellation, or resumption as an application policy. Reject results from old attempts. Do not clear all restored state as a general repair. The existing Pending Job Recovery and Durable Scheduling examples supply useful patterns.

The [original-state diagnostics](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/docs/reviews/2026-09-04-sdk-survey/evidence/group-diagnostics.log) and [scope-corrected diagnostics](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/docs/reviews/2026-09-04-sdk-survey/evidence/scoped-group-diagnostics.log) show each stage. The corrected copies still fail. No assertions were weakened and no project fixture was changed.

**The core design has several strong parts.**

The immutable Actor and the live Server share one evaluation path. Tests compare direct results with live commits. Plugin state joins the same candidate before commit. Directive validation and execution have explicit boundaries. Cancellation tests use execution barriers and check worker termination. This is a good base for deterministic orchestration.

The remote lifecycle work is substantial. Tests cover real placement, duplicate starts, uncertain startup, delayed replies, stopped requests, target restart, child loss, parent loss, and disconnect. They distinguish an unreachable child from confirmed child death. Keep that distinction in future APIs.

The recovery examples also test useful failures. Delivery restores saved intent after an Actor dies around a sink write. Job recovery uses fresh attempt identities and rejects stale results. Scheduling saves occurrence identity and acknowledges through the business result. These are better foundations for a BEAM SDK than a large collection of service adapters.

The Flow boundary fits local computation. Parallel joins and ordered Map results do not require one Actor per step. Use separate Actors when work needs an independent lifetime, mailbox, recovery rule, placement, or ownership. The recursive example currently runs application recursion inside each root Actor's execution lifecycle. It is not yet a distributed recursive Actor tree.

**The DSL should keep these boundaries visible.**

The Spark declarations, Builder, map, keyword, and Codec forms produce the same Actor definitions. Generated helpers package Signals and call the same Server API. Compile checks reject missing sources, conflicting helper names, ambiguous optional list arguments, and unknown positional fields. The full run passed these checks.

Keep inline Actions for small operations. Keep state schema, command schema, route defaults, and effect intent easy to find. Signal construction intentionally does not validate executable input. Plugin preparation can transform input before Action validation. Preserve that order and explain it with a failing-input example.

My next DSL additions would be inspection and migration support. Provide a readable definition view with routes, input schemas, Plugin state ownership, generated functions, and required runtime capabilities. Include source locations in compile errors. Define state-schema migration independently from checkpoint revision. Add a compatibility example before promising rolling upgrades of live Actors. Avoid adding a second orchestration language to describe behavior that Flows already express.

**Scale results are useful but limited.**

The existing stress command completed in 3,425.7 ms on this host. Each of 12 runs read 100,000 records and 13,768,890 bytes. Each used 4,095 recursive calls, 8,190 steps, and depth 11. The largest read contained 49 records under a limit of 64. All results matched the independent expected counts.

The new local fleet diagnostic kept 1,500 minimal Actors alive at once. Startup took 260.2 ms, one command per Actor took 91.6 ms, and shutdown took 28.9 ms. Command concurrency was 32. The observed p95 call time was 895 microseconds. Ready-VM memory increased by about 28.1 MiB. These are single-run observations, not throughput or capacity guarantees. They include neither durable storage nor distributed traffic.

The fleet stopped every Actor and checked that the instance Task Supervisor was empty. It does not prove cleanup for a 1,500-Actor ownership tree, subscriptions, timers, or resource handles. The normal hierarchy fixture has seven Actors. Those larger combined tests are the next useful step.

**Build these features and examples in this order.**

| Order | Feature or example | Required proof | Main owner |
| --- | --- | --- | --- |
| 1 | Remote command contract | New and old VMs can call each other. Expired pending work cannot enter a Turn. Lost replies have explicit outcomes. | Core |
| 2 | Stable Actor reference | Resolve an ID after PID replacement. Reject stale activations. Include instance, partition, and logical identity. | Core API plus resolver |
| 3 | Owned failover counter | Three nodes and shared storage. Kill or isolate the owner. Only a valid owner token permits accepted writes and protected effects. | Authority adapter plus core hooks |
| 4 | Recoverable worker group | Repair the current groups. Kill a worker before and after result delivery. Every accepted job has one defined terminal outcome. | Application protocol on SDK |
| 5 | Credit-based work admission | Slow workers grant bounded capacity. Test queue bytes, task limits, expired requests, tenant fairness, and overload results. | Core limits plus input Plugin |
| 6 | A 1,500-Actor review tree | Root owns directories; directories own files. Use a generated corpus. Aggregate scoped results, replace one branch, and check all cleanup counts. | Integration and scale suite |
| 7 | Sharded entity service | Place deterministic entity keys across nodes. Add a node, drain one, and transfer ownership while commands continue. | Placement package after authority |
| 8 | Capability groups | Join workers to named groups, observe membership changes, and route to suitable workers. Test duplicate, stale, and missing membership views. | Plugin or placement package |
| 9 | Bounded recursive Actor search | Spawn children only for uncertain ranges. Bound depth, calls, bytes, live Actors, and time. Cancel all descendants and reject late results. | Application example |
| 10 | Durable handoff | Worker A offers work to B; B accepts; authority transfers; A releases. Kill each participant at every boundary. | Application protocol plus authority |
| 11 | Rolling schema change | Run old and new code on separate nodes. Migrate saved state and route envelopes. Drain incompatible work and test rollback. | Core migration contract |
| 12 | Progress subscription | Observe waiting for a child, approval, retry, and output delivery. Slow or disconnect a consumer. Terminal state remains available. | Observation API |
| 13 | Owned external resource | A Plugin owns a local Port or socket. Crash it during input and output. Rebuild subscriptions and close every resource. | Plugin lifecycle |
| 14 | Replicated observations | Merge duplicate and reordered observations after a partition. Separate mergeable facts from exclusive work claims. | Application or replication adapter |

For capability discovery, OTP `pg` is a useful primitive. Its membership view can temporarily differ across nodes. Use that behavior deliberately; keep exclusive ownership separate. [Erlang process group documentation](https://www.erlang.org/doc/apps/kernel/pg.html).

Each distributed example should start actual nodes, state its delivery rules, and include loss of connection. Each recovery example should test failure before and after commit, dispatch, and acknowledgement. Each scale example should assert both work completion and cleanup. Measure accepted work, rejected work, retries, queue bytes, live Actors, live tasks, and result latency.

The existing admission limit bounds postponed Signals. [Server documentation](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/lib/jido/actor/server.ex:17) correctly says that it does not bound messages waiting to reach the callback. A larger input stream therefore needs sender-side flow control or an ingress capacity protocol. A worker-count limit alone does not provide that.

**Make the evidence easier to maintain.**

The [CI configuration](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/.github/workflows/ci.yml:26) supplies `mix test`. The [test alias](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/mix.exs:223) and [test helper](/Users/mhostetler/Source/Jido/proj_jido_core/jido_v3/test/test_helper.exs:5) exclude examples and integration tests by default. Add explicit jobs for catalog, integration, and two-node acceptance tests. Keep the research failure visible as an unresolved capability. Do not silently turn it into a passing feature claim.

Add a supported-runtime matrix and a staggered-node-start case. Derive catalog counts and commands from a small manifest so promoted examples cannot disappear from the advertised run. The top-level example command currently sounds more complete than it is. Keep the archive clearly separate from executable examples.

Before calling the distributed foundation ready, require the remote deadline tests, hibernate/thaw test, corrected group scenarios, and declared authority contract to pass. Then add one demanding ownership-tree example. That will exercise the parts of the BEAM that distinguish this SDK.

**Commands for the saved diagnostics**

Run these from the project root:

```sh
mix run docs/reviews/2026-09-04-sdk-survey/remote_api_probe.exs
mix run docs/reviews/2026-09-04-sdk-survey/fleet_probe.exs
mix test test/jido/instance_test.exs:130 --repeat-until-failure 30 --seed 0
mix test docs/reviews/2026-09-04-sdk-survey/fixed_diagnostic_test.exs docs/reviews/2026-09-04-sdk-survey/elastic_diagnostic_test.exs --include integration --seed 0
mix test docs/reviews/2026-09-04-sdk-survey/fixed_scoped_diagnostic_test.exs docs/reviews/2026-09-04-sdk-survey/elastic_scoped_diagnostic_test.exs --include integration --seed 0
```

The remote diagnostic prints observed defects and exits successfully after cleanup. It is a diagnostic, not a passing regression test. The group diagnostic tests retain the failing assertions. Their scoped variant loads a temporary replacement for the test Bus input module within that Mix invocation. It does not change the SDK or the normal test support file.
