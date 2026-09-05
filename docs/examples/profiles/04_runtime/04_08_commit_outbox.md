# Commit Outbox

Feature ID: `04_08_commit_outbox`. Status: implemented within the tested scope.

## Added feature

Business state and audit intent restore together; manual sink delivery can safely repeat. Read this after the Basic and Workflow groups.

## Use

```elixir
alias Jido.Examples.AuditOutbox

{:ok, server} = Jido.start_agent(jido, AuditOutbox)
AuditOutbox.adjust_balance(server, input: %{command_id: "command-1", amount: 10})
```

## Evidence

3 enabled tests:

- failed work creates no audit intent and dispatch is idempotent.
- a duplicate command cannot change the balance behind a deduplicated audit record.
- undelivered intent survives Agent restore and can be dispatched again.

Run:

```shell
mix test --include integration test/examples/04_runtime/04_08_commit_outbox --seed 0
```

[Source](../../../../lib/examples/04_runtime/04_08_commit_outbox/audit_outbox.ex) ·
[Tests](../../../../test/examples/04_runtime/04_08_commit_outbox/audit_outbox_test.exs)

## Boundary and next question

The sink is local and dedicated to this Agent. There is no delivery acknowledgement, automatic drain, or bounded ledger. External writes are not part of the Agent transaction.

See the [gap register](../../runtime-multi-agent-gaps.md) and
[verification report](../../runtime-multi-agent-results.md).
