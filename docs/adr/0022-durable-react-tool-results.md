# ADR 0022 — Save completed ReAct tool results within their execution

- Status: Proposed
- Date: 2026-11-24

## Context

A durable ReAct loop can restart from the beginning of an interrupted Iterate.
A completed tool call can have returned before that component saves its output.
The Session, attempt records, and reply also carry copies of tool content.

## Decision

Save a receipt with the bounded tool observation and returned effects before the
next model call. Identify the receipt by execution, ReAct run, tool round, and
position. Compare the validated call on replay. The provider call ID can change
when the model request repeats. A changed call at the same position fails the
Turn.

The Jido continuation store owns the receipt and its payloads. With the Term
codec, save each large tool payload under its digest and the Agent address.
Use references in receipts, prepared execution records, facts, and event
batches. Later Turns can reuse payloads from their input Session after the
earlier execution is collected. Load and verify the digest before decoding
the original record. Sessions with no matching stored payload keep their
inline values. Read existing execution-local receipts and references as before.

Collect receipts with the execution. Keep the immutable payloads separately so
subsequent Turns can use them. The Agent checkpoint, committed Session, and
public reply remain self-contained.

## Consequences

The Store must confirm the receipt before ReAct can use it. Work can repeat if
the tool returns before its receipt is saved and the process stops in that gap.
This receipt does not make an external tool operation atomic with a Jido write.
Recovery can send a model request again and use the saved tool result. The
receipt adds Store operations. Shared payload records keep one copy per unique
payload and Agent address. Execution collection and the Agent tombstone do not
reclaim these records. A cleanup policy must account for active references and
in-flight recoveries. Applications continue to choose whether to enable
execution compression.
