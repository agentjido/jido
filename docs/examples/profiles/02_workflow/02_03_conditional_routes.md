# Conditional Routes

- **ID:** `02_03_conditional_routes`
- **Status:** implemented
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic SDK integration
- **Tests:** 3

## SDK obligation

First-match Choice, lazy branch work, explicit failure capture, and selected-Action errors.

## Acceptance cases

- Only the first matching option runs and the fallback remains lazy.
- Explicit expected errors select fallback and permanent errors select rejection.
- A selected Action failure does not enter another option or otherwise.

## Implementation and evidence

- [Source](../../../../examples/02_workflow/02_03_conditional_routes/conditional_routes.ex)
- [Integration tests](../../../../test/examples/02_workflow/02_03_conditional_routes/conditional_routes_test.exs)
- [Workflow results](../../workflow-results.md)

Uses real Agent routing, Jido.Exec, Jido.Flow, and Server commits. External
adapters and observation callbacks only supply fixed responses and timing
controls. Caller context stays transient unless application code explicitly
copies fields into its output.

## Earlier domain examples

Conditional Fallback and Lead Qualification. See the [research archive](../../archive/workflow/README.md).
