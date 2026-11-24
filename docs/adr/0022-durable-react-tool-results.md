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

The Jido continuation store owns the receipt and its payloads. Store tool
bytes in the current execution's receipt. With the Term codec, facts and
batches can reference the receipt by slot and payload digest. A later Turn
can store earlier tool results in its own preparation with the conversation
it uses. Load and verify referenced bytes before restoring the original record.
Read older receipts and records that use separate shared payloads.

Collect receipts and preparations with the execution after settlement. The Agent
checkpoint, committed Session, and public reply remain self-contained.

## Consequences

The Store must confirm the receipt before ReAct can use it. Work can repeat if
the tool returns before its receipt is saved and the process stops in that gap.
This receipt does not make an external tool operation atomic with a Jido write.
Recovery can send a model request again and use the saved tool result. The
receipt adds Store operations during the Turn. The Turn does not add a separate
tool payload record to the Agent's retained data. Applications continue to
choose whether to enable execution compression.
