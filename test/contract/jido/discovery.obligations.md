---
modules:
  - Jido.Discovery
---

## Purpose

Protect the read-only catalog of available Action modules. This component owns
catalog startup, scan sources, Action admission, diagnostics, stable lookups,
filters, paging, and complete refresh replacement.

It does not own Action execution, permission to run an Action, Agent route
discovery, or application-specific allowlists.

## Obligations

### jido.discovery.I1 — Temporary startup and explicit readiness

- **scope:** `child_spec/1`, `ready?/0`, `catalog/0`, `last_updated/0`
- **must:** Start one temporary catalog-build Task. Before the first successful build, report not ready, return the not-initialized catalog result, and keep list and lookup reads empty. Contain startup build failures without restarting the application.
- **kind:** functional
- **status:** active

### jido.discovery.I2 — Valid scan sources and atomic replacement

- **scope:** `refresh/1`, application configuration
- **must:** Scan the selected loaded applications and add configured and call-specific modules. Accept only atom application and module lists. Deduplicate sources. Reject unavailable applications and invalid configuration. Build the complete replacement before publication, so a failed refresh keeps the prior catalog and a successful refresh does not retain stale entries.
- **kind:** functional
- **status:** active

### jido.discovery.I3 — Action-only admission and contained diagnostics

- **scope:** catalog construction
- **must:** Admit only loaded modules with a valid native Action contract. Skip non-Actions, Flows, and inline Actions. Do not run Actions or build Flows. Record load, contract, and metadata failures as sorted diagnostics without stopping valid Action discovery.
- **kind:** functional
- **status:** active

### jido.discovery.I4 — Stable catalog identity and indexes

- **scope:** catalog data, `get_action/1`, `get_action_by_slug/1`
- **must:** Publish catalog version and build time, sort Actions by name and module, retain module, owning application, name, and optional description, and derive one stable 16-character URL-safe slug from the module name. Index each Action by module and slug.
- **kind:** functional
- **status:** active

### jido.discovery.I5 — Read-only filtering and paging

- **scope:** `list_actions/1`
- **must:** Filter name and description with case-sensitive substring matches and application with exact equality. Apply offset before limit. Treat a negative or invalid offset as zero, a non-negative integer limit as a bound, and other limit values as unbounded.
- **kind:** functional
- **status:** active
