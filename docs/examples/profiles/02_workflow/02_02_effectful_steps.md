# Effectful Steps

- **ID:** `02_02_effectful_steps`
- **Status:** implemented
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic SDK integration
- **Tests:** 3

## SDK obligation

Transient caller context, effect guards, explicit output projection, idempotency, and persistence.

## Acceptance cases

- Caller context reaches Flow steps and only selected output persists and restores.
- Guard rejection prevents the call while late rejection cannot undo it.
- Context is isolated between Turns and repeated success advances only the commit revision.

## Implementation and evidence

- [Source](../../../../lib/examples/02_workflow/02_02_effectful_steps/effectful_steps.ex)
- [Integration tests](../../../../test/examples/02_workflow/02_02_effectful_steps/effectful_steps_test.exs)
- [Workflow results](../../workflow-results.md)

Uses real Agent routing, Jido.Exec, Jido.Flow, and Server commits. External
adapters and observation callbacks only supply fixed responses and timing
controls. Caller context stays transient unless application code explicitly
copies fields into its output.

## Earlier domain examples

Safe SQL, Weather Lookup, Bank Support, Metadata Search, Spreadsheet Analysis. See the [research archive](../../archive/workflow/README.md).
