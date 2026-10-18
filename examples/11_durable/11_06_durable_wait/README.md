# 11_06 Durable Wait

Status: **Proposed outline. No executable source or tests yet.**

Define an approval wait that survives BEAM loss without a blocked Action.

## Design boundary

One durable Flow remains the current Turn. Ordinary state-changing Signals wait.
An approval cannot enter through a second ordinary Turn while the first Turn is
waiting. A saved wait needs an explicit, narrowly scoped control-input contract,
or the application must end the first Flow and model approval as a later Turn.

Do not add a background execution coordinator or restore the removed Plugin path.

## Decisions and tests before implementation

- Choose a control-input contract or a sequence of separate completed Turns.
- Save the wait and its absolute deadline as portable data.
- Restore the wait without repeating completed Actions.
- Consume approval once; reject late or conflicting approval.
- Save cancellation and stop pending work.
- Define hibernation while a saved wait is active.

## Current evidence and gap

The [approval workflow](../../08_applications/08_04_approval_workflow/README.md)
uses multiple Turns. Core durable Flow Turns provide step recovery, not saved
external waits. No wait API is approved or implemented by this outline.

## Limits

A blocking Action is not a durable wait. This outline does not add a durable
mailbox or permit unrelated state-changing Turns during a pending Flow.

## Run status

There is no run command for this outline. Do not add passing placeholders or
skipped tests. Add source and a focused behavior test when this stage is built.

Previous: [Saved Completion](../11_05_saved_completion/README.md) | Next: [External Uncertainty — proposed](../11_07_external_uncertainty/README.md)
