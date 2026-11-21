# ADR 0011 — Direct Durable operation ownership

**Status** Accepted

**Date** 2026-11-19

A direct `Jido.Durable` operation drives its Runic worker to the next confirmed
stop. A competing call could replace that worker. A timeout could also leave
it active after its caller had stopped driving it.

Use one node-local lock per portable reference. It covers the direct operation
from preparation and Signal acceptance through worker cleanup. A competing call
returns `{:error, :execution_busy}`. The caller owns the worker. Caller exit
releases the lock and triggers Runic task cleanup.

Use one monotonic deadline and a private notification alias for each operation.
When the deadline expires, cancel the worker and keep the last confirmed
checkpoint for retry. Discard progress messages for the finished operation.
Synchronous storage calls and worker cleanup can finish after expiry.

Read status and results from the instance persistence profile without changing
worker registration. The checkpoint remains the authority for progress.

[Public API reference](../../guides/reference/public-api-reference.md#jidodurable)
