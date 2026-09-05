# Bounded Iteration

- **ID:** `02_06_bounded_iteration`
- **Status:** implemented
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic SDK integration
- **Tests:** 3

## SDK obligation

Initial completion, exact loop bounds, and validation of initial and replacement state.

## Acceptance cases

- Initial completion skips the body and final allowed repair succeeds.
- Exhaustion runs exactly three bodies and preserves the prior result.
- Invalid initial or replacement state stops before another iteration.

## Implementation and evidence

- [Source](../../../../lib/examples/02_workflow/02_06_bounded_iteration/bounded_iteration.ex)
- [Integration tests](../../../../test/examples/02_workflow/02_06_bounded_iteration/bounded_iteration_test.exs)
- [Workflow results](../../workflow-results.md)

Uses real Agent routing, Jido.Exec, Jido.Flow, and Server commits. External
adapters and observation callbacks only supply fixed responses and timing
controls. Caller context stays transient unless application code explicitly
copies fields into its output.

## Earlier domain examples

Structured Output Repair. See the [research archive](../../archive/workflow/README.md).
