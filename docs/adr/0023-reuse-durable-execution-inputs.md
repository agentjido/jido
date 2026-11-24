# ADR 0023 — Reuse saved input in durable execution records

- Status: Proposed
- Date: 2026-11-24

## Context

A Runic dispatch event can repeat an input value that Jido already saved
as a fact. A durable AI Turn can also repeat the same request or conversation
text in several facts and event batches. Runic can also save a Join result
as a list of values that already have fact records. These copies increase
Store writes.

## Decision

Use a fact reference in a dispatch event when the Store has confirmed the
same occurrence and value. Resolve the reference before streaming the event
to Runic. Keep older inline events readable. Store Runic fact occurrence
keys as digests in new fact manifests. Restore the full keys for recovery,
collection, and inspection.

An uncompressed Term event batch can store a repeated Runic identity once
in a dictionary for that batch. Restore the exact event bytes on read.
An uncompressed Term fact can also store a large binary value or repeated
identity once in a dictionary for that fact. Verify the fact digest after
reconstruction. Write a dictionary only when it makes the record smaller.

Store a Join result as an ordered list of fact occurrence keys when the
inputs match the saved values and the keys take less space. Rebuild the list
in memory and verify its digest on recovery. Keep the full-value format for
Join results that do not meet these conditions.

With the Term codec, facts and batches can refer to large request and
conversation text in the confirmed preparation for the same AI Turn.
Verify the text digest and restore the original record before replay.
A preparation cannot refer to itself. A missing source fails recovery if a
saved record refers to it.

A settled direct Flow keeps its Turn ID, status, and expiry in the Agent
checkpoint. Keep any wait retry receipt and any terminal result that awaits
acknowledgement. Leave the original admission data in the running receipt
while recovery still needs it. Continue to read older settled receipts.

## Consequences

These changes use the existing execution identity and collection lifetime.
They add sources to the execution reference format. Agent state, Session,
and reply formats stay the same. Recovery may read a preparation before
it can load a fact or stream a batch. Recovery can load saved contributions
to rebuild a Join result. Older Jido versions cannot read the new
execution formats and compact settled receipts.
