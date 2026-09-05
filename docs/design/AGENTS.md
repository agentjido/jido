# Design documentation instructions

These instructions apply to all files in `docs/design`.

## Review status

The **Document review status** table in `README.md` is the source of truth for
user approval. Design maturity labels such as `Proposal`, `Locked for Jido
core`, or `Proposed decision` do not mean that the user approved a document.

Use only these review values:

- `Pending approval`
- `Approved`

When an agent changes a design document, the agent must set that document's
row to `Pending approval` before it finishes the task. This rule applies to all
changes, including small editorial changes.

When an agent adds a design document, the agent must add it to the table with
`Pending approval`.

An agent must not set a document to `Approved` unless the user explicitly
names that document as approved. Do not infer approval from general positive
feedback or from a request to continue.

Changing only the review-status table does not reset the review status of
`README.md`. Any other agent change to `README.md` resets its row to `Pending
approval`.
