# Current-main maintenance audit

Read-only fetch of `origin/main` on 2026-09-05 returned
`99aa07cc90a494bf3e69332bcb6c8c0086884381`. No new main commits appeared beyond the
seven commits recorded in the approved plan. Core history remains intact.

| Main change | V3 result and proof |
| --- | --- |
| `99aa07cc` optional state size | Added the complete-state limit to V3 construction, Builder, DSL, Codec, transition, restore and live finalization. Fourteen state-budget tests include Plugin state, raw struct changes, persistence and runtime checkpoints. Retired Strategy/StateOps/Memory/Thread helpers remain retired; their replacements use the same state validation. |
| `2d2ab51d` safe validation transport | Ported scalar path preservation and invalid UTF-8 handling. Eight transport tests retain the main assertions, including actual Zoi errors through Exec, observation and JSON. |
| `8f8f9e49` tracker removal | No beadwork code, command, dependency, or active workflow was restored. |
| `7dc12069` routing guide | The rewritten guide states shallow defaults with Signal values taking precedence and the V3 requirement for exactly one selected executable. |
| `2b05de80` metrics | Updated telemetry_metrics from 1.1.0 to 1.2.0 and the declared range to `~> 1.2`. |
| `d30c5f7a` CI | Retained the Blacksmith Linux runner. Explicit acceptance and QA jobs are added with M13/M14. |
| `adf3e058` dependencies | Carried Req 0.7.3 and git_ops 2.12.2. Kept Action beta.6, Signal beta.2, Spark, and SchedEx 1.2.1. The removed poolboy API has no callers or lock entry. |

Mint moved from 1.9.3 to the main lockfile's 1.10.0. The old dependency download
record reported advisories EEF-CVE-2026-82729 and EEF-CVE-2026-82728.
The final beta dependency audit remains part of M14. Dependency resolution passed;
see `evidence/core/m12-deps-final.json` and its log.

The first protection run had 98 passes and one failure in a new test. The test
used `state` where Server startup requires `initial_state`. The corrected test
uses the actual public option; the runtime did not change for that failure.
The next protection run passed all 99 selected tests. The lifecycle and extended
budget run passed 21 tests. Seven lifecycle tests restore explicit coverage of
attachment, owner death, detach, touch, stale timers, and real idle shutdown.

The guide audit corrected the initial claim that attachment and idle controls
were removed. Those controls remain on AgentServer. The old InstanceManager
facade and pre-warmed pool remain removed. RAM runtime checkpoints also remain;
they do not provide VM durability. See `guides/runtime.md` and `guides/storage.md`.

All 278 old files and 2,299 old test identities have entries in
`legacy-dispositions.json`. The summary separates 361 retained test identities,
1,478 replacement V3 contracts, 454 retired V2 interfaces, and six removed Sensor
error-convenience checks. A retained name alone is not a claim of unchanged API
semantics. Exact-byte retained files are identified separately. Each entry links
to a migration guide and current checks. The final complete gate verifies those
check selections again.

The transfer ledger now accounts for all 667 frozen donor paths. Historical
research and reviews remain labelled as earlier evidence. Every design document
remains Pending approval. The current guides describe the implemented contract;
the proposal Ref facade and replacement Plugin/persistence designs remain deferred.
`CHANGELOG.md` has not been edited.

The first full M12 run had 1,039 passes, one failure and the approved exclusion.
Its failed exact-field assertion omitted the new state-size field. The update
adds that field and checks its nil default; all prior fields remain required.
The first compile also found a generated getter reading a missing configuration
key. The DSL defaults now include the nil limit. Compilation with warnings as
errors then passed. Failed records remain in `evidence/core/m12-compile.json`
and `m12-test.json`.
