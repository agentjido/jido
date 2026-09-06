# Sequential Flow

- **ID:** `02_01_sequential_flow`
- **Status:** implemented
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic SDK integration
- **Tests:** 4

## SDK obligation

Input and output schemas, result dependencies, control dependencies, and one complete commit.

## Acceptance cases

- Dependencies hold intermediate state and direct/live output agrees.
- An intermediate failure stops its dependent and keeps an existing commit.
- Flow input, Flow output, and Agent candidate schemas reject at distinct boundaries.
- The short double and gate bodies are inline Steps. The compiled double target
  supports new Builder bindings and a JSON round trip alongside the named Finish Action.

## Implementation and evidence

- [Source](../../../../examples/02_workflow/02_01_sequential_flow/sequential_flow.ex)
- [Integration tests](../../../../test/examples/02_workflow/02_01_sequential_flow/sequential_flow_test.exs)
- [Workflow results](../../workflow-results.md)

Uses real Agent routing, Jido.Exec, Jido.Flow, and Server commits. External
adapters and observation callbacks only supply fixed responses and timing
controls. Caller context stays transient unless application code explicitly
copies fields into its output.

## Earlier domain examples

Sequential Data Flow; terminal validation from Trip Itinerary. See the [research archive](../../archive/workflow/README.md).
