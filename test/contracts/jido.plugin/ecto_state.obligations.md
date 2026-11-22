---
modules:
  - Jido.Plugin.EctoState
  - Jido.Plugin.EctoState.Update
---

## Purpose

Use a row from the application's Ecto schema as the source of Agent domain
state. The application owns its Repo, row, and changeset.

## Obligations

### jido.plugin.ecto_state.I1 — Exclusive use of the Ecto schema

- **scope:** `Jido.Plugin.EctoState` authoring
- **must:** Lower an Ecto schema declaration to one Plugin provider with that schema. Reject an additional Joi domain schema through other definition paths. List the Plugin when the optional Ecto integration is present.
- **kind:** functional
- **status:** active
