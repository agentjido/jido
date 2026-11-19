---
modules:
  - Jido.Session
  - Jido.AI.Thread.Projection
---

## Purpose

Protect the portable Session and its projection into ReqLLM messages. This
component owns Session revision rules, message encoding, complete tool
exchanges, and bounded context selection. It uses the ordered history from
`jido.thread`.

## Obligations

### jido_ai.conversation.I1 — Portable revisioned Session

- **scope:** `Jido.Session`
- **must:** Advance the Session revision consistently with changes to its
  Thread and preserve the nested history through Session encode and decode.
- **kind:** persisted-format
- **status:** active

### jido_ai.conversation.I2 — Complete exchanges only

- **scope:** `Jido.AI.Thread.Projection.context/2`, `project/2`, `explain/2`
- **must:** Include an assistant tool request only when every call has one matching tool result. Assemble complete exchanges in chronological order with a linear list pass. Exclude incomplete exchanges without changing stored Thread entries.
- **kind:** functional
- **status:** active

### jido_ai.conversation.I3 — Observations stay outside model history

- **scope:** `Jido.AI.Thread.Projection.observe/5`, conversation projection
- **must:** Keep model attempts, tool attempts, review records, and request outcomes in the Thread while excluding them from ReqLLM message history.
- **kind:** security
- **status:** active

### jido_ai.conversation.I4 — Context limits keep recent complete turns

- **scope:** `Jido.AI.Thread.Projection.context/2`, `project/2`
- **must:** Apply message and byte limits to complete conversation turns. Keep the newest complete turn when older turns exceed a configured limit.
- **kind:** functional
- **status:** active

### jido_ai.conversation.I5 — Tool content parts survive projection

- **scope:** tool message encoding and ReqLLM restoration
- **must:** Preserve valid text, image, and file content parts, structured tool output metadata, tool call identity, and reasoning details through Thread storage and context restoration.
- **kind:** persisted-format
- **status:** active

### jido_ai.conversation.I6 — Validate the portable Session boundary

- **scope:** `Jido.Session`
- **must:** Enforce portable Session invariants in Agent state. Read supported version 1 fields and defaults. Return a tagged error for conflicting fields and malformed nested data.
- **kind:** persisted-format
- **status:** active
