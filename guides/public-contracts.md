# Public contract test register

These IDs identify public promises. A passed test is evidence for its declared cases.
It does not prove all possible inputs or process schedules. Property and fuzz reports
keep separate results. A missing case or failed run supplies no passed evidence.

| ID | Public promise | Required cases |
| --- | --- | --- |
| AGT-001 | Definitions and Codec contain static authoring data; instances keep separate identity and state. | Neutral and instance definitions; wire round trip; malformed instance. |
| AGT-002 | Instance and candidate state satisfy the complete schema; source values remain unchanged. | Defaults, depth 0–70 nested defaults, object intersections, nullable and invalid nil, optional fields, invalid state, schema policy, transition histories. |
| TURN-001 | Each valid Signal selects one Action or Flow. | Ordered routes, missing routes, malformed types, custom selection, source binding. |
| TURN-002 | The complete candidate and Directive batch validate before commit. | Valid batch, invalid state, invalid Directive at each position. |
| TURN-003 | A failed Turn before commit preserves the committed snapshot and revision. | Mixed successful and failed histories, next successful Turn. |
| EFFECT-001 | Direct commands return ordered effects; live effects run after commit. | Ordered effects, first failure stops remaining effects, committed state retained. |
| PLUG-001 | Plugin input and state stay within their owner; callbacks follow declaration order. | Valid callbacks, ownership violations, callback faults. |
| LIFE-001 | AgentServer admits serial Turns and owns execution cancellation and cleanup. | Blocked cancellation, server death, stale messages from a previous Turn. |
| PERS-001 | Checkpoints validate identity, version, portability, and state before recovery. | Local store round trip, invalid identity, version and state, nonportable values. |
| TRACE-001 | Trace and cause fields propagate; captured context restores after success and failure. | Carrier fields, child span, cause, previous context restored. |
| ERROR-001 | Public error output is bounded and sanitizes secret fields; retry status follows the error contract. | Atom and string keys, nested lists and tuples, depth and size, invalid binary. |
| TOPO-001 | Additive Topology updates preserve each existing exact specification. | Unchanged and added specs, changed and removed specs, integer and float distinctions. |

Run `mix test.property` for short generated checks. Run `mix test.fuzz` for longer
checks. Both use seed 0 by default. Pass `--seed N` to select another seed.
Default tests exclude these suites. CI, `mix quality`, and `mix test.all` include
the short property suite. The longer fuzz suite runs separately.

The support runs fixed examples and saved inputs before generated inputs. It uses
StreamData for generation and bounded shrinking. Inputs must be plain JSON data.
Runtime resources are created inside each attempt and must be stopped before the
attempt returns. Process monitors and event barriers establish completion.

The report is `_build/test/property-report.json`. Measurements and reduced failures
are under `_build/test/property-fuzz/` and `_build/test/property-counterexamples/`.
Copy a confirmed reduced input into `test/property/corpus/<fuzz_id>/` to retain it.
Records include seed, limits, source revision and digest, dirty state, loaded Action
and Signal sources, runtime versions, generated samples, replay and shrink counts,
and observed cases. Missing measurements prevent passed contract evidence.

The time limit applies between StreamData attempts. ExUnit supplies the outer test
limit. A killed test cannot finish cleanup; its report remains incomplete or failed.
These tests cover selected schedules and local adapters. External service checks
remain in their existing opt-in suites.

The separate intersection checks use seed 389 and assert their exact input count.
They cover branch order, defaults, overlapping fields, conflicts, missing fields,
nullable values, and refinement counts. Their counts are printed in the test output.

## Agent Covenant gate

The `jido.agent` Covenant component refines AGT-001, AGT-002, TURN-001,
TURN-002, the direct-command part of EFFECT-001, PLUG-001, and Agent error
handling. Its 25 active obligations cover authoring, definition data, instances,
and direct commands. The tests use public entry points and fresh DSL fixtures.
Checkpoint storage and live AgentServer behavior keep their separate tests.

Run `mix test.contract` for passing-test obligation coverage. `mix test.ci`
runs the core and property checks, then this contract gate. For a focused
mutation check of the three test gaps found during this rollout, run:

```sh
MIX_ENV=test mix covenant.mutate jido.agent --macros \
  --only m0684,m0985,m1034 --jobs 1 --seed 0 --timeout 5000 \
  --max-runtime 120000 --out tmp/covenant/agent-focused.json
```

The development dependency is the sibling `../covenant` fork on
`feat/macro-mutation`. Setup, scope, survivor review rules, and tool limits are
in the repository's `test/contracts/README.md`. That file also gives the separate
full-run command. Mutant IDs depend on the source and module profile; check the
reported sites after a source change. The obligation report is
`test/contracts/coverage.json`. The earlier full run and current focused result are
recorded in `test/contracts/jido/agent.baseline.md`. A focused result does not verify
the full mutation profile. A passing obligation report does not replace mutation
review or the package line-coverage gate.
