---
modules:
  - Jido.Statechart
  - Jido.Statechart.BasicHTTP
  - Jido.Statechart.Configuration
  - Jido.Statechart.Error
  - Jido.Statechart.Error.InvalidChart
  - Jido.Statechart.SCXML
  - Jido.Statechart.SCXML.Reference
  - Jido.Statechart.SCXML.Unsupported
  - Jido.Statechart.Sends
  - Jido.Statechart.Turn
  - Jido.Statechart.Turn.Advance
  - Jido.Statechart.Turn.Microstep
  - Jido.Plugin.Statechart
  - Jido.Plugin.Statechart.Commit
  - Jido.Plugin.Statechart.Route
  - Jido.Plugin.Statechart.Effects
---

## Purpose

Compile supported SCXML and run chart sessions on Jido Agents.

## Obligations

### jido.plugin.statechart.I1 — Chart compilation

- **scope:** `Jido.Statechart`, `Jido.Statechart.SCXML`
- **must:** Compile supported SCXML 1.0. Return a typed error from `compile/1` for invalid input and unsupported chart features.
- **kind:** functional
- **status:** active

### jido.plugin.statechart.I2 — Standalone startup

- **scope:** `Jido.Statechart.spawn/3`
- **must:** Return the new Agent only after chart initialization commits. Stop the new Agent if its initialization fails. Preserve an existing Agent if its ID is already in use.
- **kind:** functional
- **status:** active

### jido.plugin.statechart.I3 — Session transitions

- **scope:** `Jido.Plugin.Statechart`, `Jido.Statechart.Turn`
- **must:** Require initialization before a chart event. Commit stable configurations, preserve completed sessions, and leave the session unchanged when stabilization exceeds its bound.
- **kind:** functional
- **status:** active
