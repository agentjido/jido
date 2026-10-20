---
modules:
  - Jido.Plugin
  - Jido.Plugin.DirectiveContext
  - Jido.Plugin.Error
  - Jido.Plugin.Init
  - Jido.Plugin.Input
  - Jido.Plugin.Manifest
  - Jido.Plugin.Normalizer
  - Jido.Plugin.SignalContext
  - Jido.Plugin.Spec
---

## Purpose

Protect the generic Plugin declaration and callback contract. This component
defines valid Plugin metadata and callback shapes. It does not define when a
consumer runs a callback or what a bundled Plugin does.

## Obligations

### jido.plugin.I1 — Plugin declaration and identity

- **scope:** `use Jido.Plugin`, `Jido.Plugin.manifest/1`
- **must:** Define one Plugin module with a stable ID, positive version, static manifest, and optional Agent, AgentServer, and persistence callback groups. Reject unknown or removed role and facet selectors. Require the Plugin behavior and generated marker.
- **why:** A Plugin declaration must have one current source of identity and capability metadata.
- **kind:** functional
- **status:** active

### jido.plugin.I2 — Callback ownership discovery

- **scope:** `Jido.Plugin.owner_callbacks/0`, `Jido.Plugin.Manifest`
- **must:** Select an owner only from documented callback names and arities. Keep owner order fixed as Agent, AgentServer, and persistence. Do not select an owner from arbitrary helper functions. Require selected callbacks to belong to the Plugin module.
- **why:** Capability discovery must not depend on naming accidents or hidden facet modules.
- **kind:** functional
- **status:** active

### jido.plugin.I3 — Manifest and option validation

- **scope:** `Jido.Plugin.Manifest.validate/2`, `Jido.Plugin.Manifest.options_for/3`
- **must:** Require a valid module, positive version, at least one selected owner, and a valid owner-to-option-key map. Keep keys unique, assign every declared option when a map is present, reject mappings to unselected or unknown owners, and require static option data. Give each owner only its assigned options.
- **why:** Each consumer must receive a stable and isolated configuration view.
- **kind:** functional
- **status:** active

### jido.plugin.I4 — Declaration normalization

- **scope:** `Jido.Plugin.Normalizer.normalize_all/1`, `canonical_declarations/1`, `declarations/1`
- **must:** Accept Plugin modules, module-and-keyword declarations, or a complete list of normalized Specs. Preserve declaration order and exact common options. Reject malformed declarations, unloaded modules, incomplete Specs, mixed Specs and declarations, repeated Plugin modules, and mismatched marker metadata. Reusing a normalized Spec must not run declaration callbacks again.
- **why:** Authoring and runtime consumers need one canonical Plugin declaration without repeated callback work.
- **kind:** functional
- **status:** active

### jido.plugin.I5 — Agent callback declaration shapes

- **scope:** Agent callbacks declared by `Jido.Plugin`, `Jido.Plugin.Normalizer`
- **must:** Accept no owned state or one safe atom key with a static Zoi schema. Accept a unique list of loaded Directive struct modules with Directive-owned validation. Require `reduce/2` to have owned state. Require every declared Directive type to have either reduction or runtime dispatch. Reject built-in Directive ownership and duplicate state keys or Directive owners across Plugins.
- **why:** The generic interface must define valid ownership before Agent evaluation starts.
- **kind:** functional
- **status:** active

### jido.plugin.I6 — Server and persistence callback declaration shapes

- **scope:** AgentServer and persistence callbacks declared by `Jido.Plugin`, `Jido.Plugin.Normalizer`
- **must:** Require one documented AgentServer capability in addition to option validation. Preserve explicit option-validation errors and reject other results. Pair quiesce with resume. Require runtime dispatch to own Directive types. Require persistence dump and load together and require one Agent-owned state field.
- **why:** A valid declaration must not advertise a callback group that its consumer cannot use.
- **kind:** functional
- **status:** active

### jido.plugin.I7 — Callback fault containment

- **scope:** Plugin marker, state, Directive, and option callbacks used during normalization
- **must:** Convert callback raises, throws, and exits to Plugin-scoped execution errors with the package, callback, and original failure data. Preserve an explicit callback error when the callback result shape is unambiguous. Treat `{:error, schema}` from `state_spec/1` as state owned under the valid `:error` key. Reject an invalid callback result with a structured Plugin error.
- **why:** A declaration fault must not escape as an unrelated process failure.
- **kind:** functional
- **status:** active

### jido.plugin.I9 — Generic Plugin context values

- **scope:** `Jido.Plugin.Input`, `Jido.Plugin.Init`, `Jido.Plugin.SignalContext`, `Jido.Plugin.DirectiveContext`
- **must:** Keep prepared and runtime input separate. Validate runtime initialization and narrow Signal and Directive contexts with their required identity, Signal, version, owned-state, option, instance, and partition fields. Supply only documented empty defaults. Do not place live handles or complete Agent values in these generic structs.
- **why:** Consumers need narrow handoff values that do not create a second Agent state or leak full runtime ownership.
- **kind:** functional
- **status:** active
