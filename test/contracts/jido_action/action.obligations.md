---
modules: [Jido.Action, Jido.Authoring.Compiler, Jido.Authoring.Config]
---

# Action macro obligations

## Purpose

Check `use Jido.Action` with the existing Action tests. The API source remains
the `Jido.Action` module documentation and `guides/actions.md`.
The macro check recompiles `test/support/fixtures/action/definitions.ex`
before the contract test file. Tests also compile their own Action modules.
The shared authoring modules are checked through Action and Flow callers,
using the existing authoring tests. This does not establish complete Flow
contract coverage.

### jido_action.action.I1 — Generated metadata describes the declared Action
- **scope:** `Jido.Action.__using__/1`
- **must:** Generate name/0, description/0, schema/0, output_schema/0, and authoring_contract/0 from the declared options. Preserve the static input and output schemas. Use `Zoi.map()` when schemas are absent. Reject non-Zoi schema values. Return JSON-safe descriptions and report schemas or metadata that cannot be represented as JSON. Retain the Action kind; shared Flow modules retain their Flow kind and cannot be selected as Actions. Generated validators use the declared schemas and input preparation callback. Tool description projection can fail when authoring_contract/0 is called even after successful compilation.
- **kind:** functional
- **status:** active

### jido_action.action.I2 — Configuration is static and validated during compilation
- **scope:** `Jido.Action.__using__/1`, `Jido.Authoring.Compiler.__using__/1`, `Jido.Authoring.Config.prepare!/3`
- **must:** Require a non-blank UTF-8 name within the documented byte limit. Reject unknown options and schemas that cannot accept maps. Support literal and computed options and named MFA schema effects. Reject anonymous functions and lazy schemas in stored schema data. Evaluate options and schema builders once during compilation, without repeating that work when metadata or validation functions are called. Require run/2 and stop compilation when it is missing.
- **kind:** functional
- **status:** active
