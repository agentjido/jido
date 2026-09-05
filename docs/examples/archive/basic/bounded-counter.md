> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Bounded Counter

- **Status:** archived research
- **Complexity level:** 1 - Foundation
- **Feature group:** basic
- **Test class:** local deterministic

## Profile

- **Purpose:** Add a simple state invariant to the Counter.
- **User story:** As an operator, I keep a count inside a configured minimum and maximum.
- **Trigger or input:** A counter change Signal with a signed integer delta.
- **Agent state:** `count`, `minimum`, and `maximum`.
- **Actions or Flow:** One Action calculates the candidate value and rejects values outside the bounds.
- **External interactions:** None.
- **Runtime Directives or capabilities:** None.
- **Expected result:** Valid values commit once. Invalid values return a structured error and keep prior state.
- **Failure cases:** Bad delta type or out-of-range value.
- **Jido features under pressure:** Zoi refinements, error shape, no partial state, and state invariants.
- **Source framework and links:** [Akka: actor behavior and immutable messages](https://doc.akka.io/libraries/akka-core/current/typed/actors.html), and [Basic SDK suite](../../../../test/examples/01_basic/README.md)

## Burn-in result

**Passed.** A valid change commits one new state. An out-of-range change returns
a structured error and does not commit. Rejection metrics and duplicate Signal
handling are application policies, not requirements of this example. See the
[basic results](../../basic-results.md).

## Current scope

This is an archived research profile from the original catalog. Its source
folder and repeated domain tests were removed. It is not a current SDK
acceptance claim. See the [five Basic fixtures](../../../../test/examples/01_basic/README.md)
and [current results](../../basic-results.md) for the implemented obligations.
