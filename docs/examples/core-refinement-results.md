# Core extension refinement

Date: 2026-09-06. Branch: `v3-spike`. Baseline: `b25084ee`.

This pass covers three simplifications: dependency scope, design consistency,
and the Scheduler/Topology extension points. It creates no new packages.

## Changes and proof

| Change | Integration evidence | Limit |
| --- | --- | --- |
| Keep `req_llm` and `dotenvy` in development and test | All 62 factory tests pass. Production compilation and Hex metadata exclude both dependencies. | Examples still use the existing dependencies in development and test. |
| Configure Scheduler `delivery_interval` | The File-backed recovery fixture rejects result writes. Two attempts retain the same saved occurrence and respect a 250 ms delay. A successful result commit clears the pending work. | The one-pending-occurrence, skip, identity, and acknowledgement rules remain. |
| Add Topology manual repair and `Controller.reconcile/2` | The Independent DSL example stops one Agent. Manual mode leaves it stopped until a request. Repair creates a replacement while the other Agent retains its PID and state. | The controller repairs the existing target; it does not update a live definition or place Agents across nodes. |
| Keep repair concurrency bounded | Ten requests during blocked startup use the existing concurrency limit of one and produce one follow-up pass. Both Agents become ready with no duplicate starts. | The application selects request timing. It cannot replace core activation or ownership checks. |
| Identify the current design baseline | The core scope guide lists supported APIs and deferred contracts. Changed Markdown links resolve. ExDoc builds with warnings as errors. | Earlier proposals remain available and Pending approval. They are not active removal instructions. |

The two behavior probes were added before the runtime changes. The first run
passed seven of nine tests. Manual repair failed because the option and public
operation were absent. Scheduler delivery retried after 105 ms despite a
configured 250 ms interval. Both probes pass after the changes.

The pass reuses the existing Scheduler recovery fixtures, DSL-authored Agents,
Topology examples, and application tests. It adds no parallel example runtime.
The new example check uses the shared `:example` tag and remains excluded by
default. Core regression checks remain part of the default suite.

## Verification

| Check | Result |
| --- | --- |
| Factory examples after dependency change | 62 passed |
| Scheduler, Topology, and application integration checks | 108 passed |
| Durable scheduling profile command | 31 passed |
| Independent example without `--include example` | Both checks excluded, including the new repair test |
| Complete suite with coverage | 1,256 passed; the same 11 research failures; one existing exclusion |
| Core coverage | 93.6%; repository minimum remains 90% |
| `mix quality` | Passed: format, compile, Credo, and Dialyzer |
| `mix docs --warnings-as-errors` | Passed; new guide and README link generated |
| Production compilation with warnings as errors | Passed; 183 core modules, no example or test modules |
| Hex archive | 156 entries; new guide included; no example or test files |
| Hex requirements and production dependency graph | No `req_llm` or `dotenvy` |

Run the full suite, including known research failures, with:

```sh
mix test --include example --include flaky --seed 0 --cover
```

The complete run took 569 seconds. Its 11 failing test names match the
pre-refinement baseline exactly. Five new regression checks pass. Exit status
2 comes from the existing research assertions; it is not a fully passing suite.

The existing [feature probes](feature-acceptance-results.md) and
[live-upgrade probes](live-upgrade-results.md) remain enabled. This refinement
does not implement their missing route, Plugin, persistence, identity, or
upgrade contracts. The distributed authority example still requires an
explicit authority outside core. Proposed durable, cluster, and transport
package ownership remains a separate decision.

See the [core scope guide](../../guides/core-scope.md) for supported APIs and
configuration examples.
