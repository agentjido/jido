# Recoverable Effects

A successful Agent Turn can commit state before a Directive completes. This is
an intentional boundary: Agent state is atomic, but an external system is not
part of the same transaction.

Use a recoverable effect protocol when work must survive process or node
failure.

## Store intent before execution

A common protocol has four steps:

1. Create a stable operation ID.
2. Commit a pending operation in Agent state.
3. Execute the external operation with that ID as an idempotency key.
4. Send an acknowledgement Signal that removes or completes the pending item.

The Directive that starts the operation comes from the same Turn that records
the pending intent. If the actor stops after commit, restore can see the pending
item and issue the work again.

```elixir
%{
  pending: %{
    "payment-018" => %{
      kind: :capture_payment,
      order_id: "order-42",
      amount_cents: 2_500
    }
  }
}
```

The external receiver must treat the stable ID as idempotent. Jido cannot make
an arbitrary external API atomic with Agent state.

## Keep durable facts in state

Ordinary Directive structs are transient Turn outputs. Do not use a Directive
list as a durable outbox. Store the business intent in validated Agent or Plugin
state. Then, derive the next Directive from that state.

Use a bounded structure and define retention. Unbounded pending work can make
every checkpoint more expensive.

## Use schedules for time-based work

`Jido.Plugin.Scheduler` stores durable schedule definitions and occurrence
state. It can recover an occurrence that was reserved before a crash. The
target operation must still be idempotent because recovery can repeat delivery.

For general messages, Jido Signal supplies buses and dispatch adapters. A bus
can transport an acknowledgement back to the owning actor. But transport alone
does not make the business operation durable.

## Classify outcomes

Design each external operation for these states:

- not started
- started with an unknown result
- confirmed complete
- confirmed failed and safe to retry
- permanently failed and needs compensation or operator action

Keep enough information in portable state to make the next decision after
restore. Do not store a PID, task reference, or client connection as evidence
that an operation is active.

## Observe the boundary

Telemetry and audit records can show that a Turn committed and that a Directive
later failed. They help diagnosis, but they are not the recovery protocol. The
pending operation in state is the source of truth.

For a complete example, see `test/examples/04_runtime/04_08_commit_outbox` in
the repository.
