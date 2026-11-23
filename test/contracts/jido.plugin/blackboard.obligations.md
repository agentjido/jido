---
modules:
  - Jido.Blackboard
  - Jido.Blackboard.Server
  - Jido.Plugin.Blackboard.Server
  - Jido.Plugin.Blackboard.Client
  - Jido.Plugin.Blackboard.Client.Patch
---

## Purpose

An opt-in board shares current facts between Agents on one node. The board
owns its data and revision. AgentServer owns Turn commit and effect ordering.

## Obligations

### jido.plugin.blackboard.I1 — Board ownership and identity

- **scope:** `Jido.Plugin.Blackboard.Server`, `Jido.Blackboard.read/3`
- **must:** A board has one owner per instance and name. Stopping the owner releases the board. A replacement starts with initial data and rejects old revisions.
- **kind:** functional
- **status:** active

### jido.plugin.blackboard.I2 — Conditional update

- **scope:** `Jido.Blackboard.patch/6`, `Jido.Blackboard.Server`
- **must:** Apply valid changes and removals together when the revision matches. Advance the revision for an accepted patch. Preserve the old snapshot on conflict or invalid input.
- **kind:** ordering
- **status:** active

### jido.plugin.blackboard.I3 — Live and direct input

- **scope:** `Jido.Plugin.Blackboard.Client.admit/3`
- **must:** Supply a current snapshot on selected live Signals and report unavailable boards. Allow other Signals and allow direct evaluation with explicit input.
- **kind:** functional
- **status:** active

### jido.plugin.blackboard.I4 — Post-commit outcome

- **scope:** `Jido.Plugin.Blackboard.Client.dispatch/4`, `Jido.Plugin.Blackboard.Client.Patch.validate/1`
- **must:** Reject invalid patch Directives before commit. Dispatch valid patches after commit and report the outcome with the same request ID. Report a timeout even if the write can still apply.
- **kind:** ordering
- **status:** active
