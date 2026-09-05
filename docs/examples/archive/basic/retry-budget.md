> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Retry Budget

- **Status:** archived research
- **Complexity level:** 1 - Foundation
- **Feature group:** basic
- **Test class:** local deterministic

## Profile

- **Purpose:** Make bounded retry policy visible in Actor state.
- **User story:** As an operator, I can see how many attempts remain for one operation.
- **Trigger or input:** Attempt succeeded, failed, or reset Signal.
- **Agent state:** Operation ID, attempt count, maximum attempts, last error class, and status.
- **Actions or Flow:** One Action applies the attempt result and calculates whether another attempt is allowed.
- **External interactions:** None. A parent example supplies the actual operation.
- **Runtime Directives or capabilities:** None. A later runtime example can schedule the next attempt.
- **Expected result:** The budget never exceeds its limit and exhausted work becomes terminal.
- **Failure cases:** Mismatched operation ID, late result, invalid limit, or duplicate attempt result.
- **Jido features under pressure:** Retry policy, correlation, stale Signal rejection, and schedule intent.
- **Source framework and links:** [PydanticAI: retries](https://pydantic.dev/docs/ai/core-concepts/retries/), and [Basic SDK suite](../../../../test/examples/01_basic/README.md)

## Current scope

This is an archived research profile from the original catalog. Its source
folder and repeated domain tests were removed. It is not a current SDK
acceptance claim. See the [five Basic fixtures](../../../../test/examples/01_basic/README.md)
and [current results](../../basic-results.md) for the implemented obligations.
