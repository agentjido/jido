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
