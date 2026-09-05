# Nested Flow

- **ID:** `02_07_nested_flow`
- **Status:** implemented
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic SDK integration
- **Tests:** 4

## SDK obligation

Separate child result scopes, shared context, child schemas, typed failures, and shared timeout.

## Acceptance cases

- Child calls keep separate results and share context without intermediate commits.
- Child input and output contracts stop the parent and preserve its prior commit.
- A nested Action error keeps its typed cause and the parent can run again.
- The parent execution timeout also stops a blocked child.

## Implementation and evidence

- [Source](../../../../lib/examples/02_workflow/02_07_nested_flow/nested_flow.ex)
- [Integration tests](../../../../test/examples/02_workflow/02_07_nested_flow/nested_flow_test.exs)
- [Workflow results](../../workflow-results.md)

Uses real Agent routing, Jido.Exec, Jido.Flow, and Server commits. External
adapters and observation callbacks only supply fixed responses and timing
controls. Caller context stays transient unless application code explicitly
copies fields into its output.

## Earlier domain examples

Writer and Editor. See the [research archive](../../archive/workflow/README.md).
