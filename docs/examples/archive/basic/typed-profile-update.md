> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Typed Profile Update

- **Status:** archived research
- **Complexity level:** 1 - Foundation
- **Feature group:** basic
- **Test class:** local deterministic

## Profile

- **Purpose:** Show a nested Zoi-first input and state contract.
- **User story:** As a user, I update selected profile fields and keep all other fields.
- **Trigger or input:** `profile.update` Signal with a typed patch.
- **Agent state:** Name, locale, and notification settings.
- **Actions or Flow:** One Action validates and normalizes the patch, then returns the complete state.
- **External interactions:** None.
- **Runtime Directives or capabilities:** None.
- **Expected result:** The normalized profile commits once and keeps all fields not present in the patch.
- **Failure cases:** Unknown field, invalid locale, invalid nested data, or empty update.
- **Jido features under pressure:** Zoi object schemas, deep update rules, stable public errors, and portable state.
- **Source framework and links:** [PydanticAI: Pydantic model example](https://pydantic.dev/docs/ai/examples/getting-started/pydantic-model/), and [Basic SDK suite](../../../../test/examples/01_basic/README.md)

## Current scope

This is an archived research profile from the original catalog. Its source
folder and repeated domain tests were removed. It is not a current SDK
acceptance claim. See the [five Basic fixtures](../../../../test/examples/01_basic/README.md)
and [current results](../../basic-results.md) for the implemented obligations.
