---
modules: [Jido.Instruction]
---

# Instruction obligations

## Purpose

Check the public Instruction contract with the existing unit and property
tests. The API source remains `Jido.Instruction` module documentation and
`guides/instructions.md`. These obligations refine the existing `INS-001`
and `TARGET-001` contract IDs.

### jido_action.instruction.I2 — Binding validates templates and keeps raw parameters
- **scope:** `Jido.Instruction.bind/4`, `Jido.Instruction.validate_template/1`
- **must:** Build inert templates with the declared kind, module, metadata, and empty params/context without loading the target. Reject invalid templates, nonempty template parameters or context, and invalid template metadata. Require map context and runtime metadata. Keep parameters unchanged until target validation. Check the current target kind and callbacks. Merge runtime metadata over equal template keys and preserve other template metadata. Return structured errors for rejected input.
- **kind:** functional
- **status:** active

### jido_action.instruction.I3 — Construction normalizes call data and rejects removed fields
- **scope:** `Jido.Instruction.new/1`
- **must:** Accept atom-keyed maps and keyword lists. Require a supported target and return a resolved Instruction with kind, target, params, context, and metadata. Normalize keyword call data and nil fields to maps. Reject invalid call data and removed id, action, flow, or opts fields with structured errors. Report removed fields in stable order and reject a declared kind that disagrees with the current target. new!/1 returns the same resolved Instruction or raises the underlying construction error.
- **kind:** functional
- **status:** active

### jido_action.instruction.I4 — Resolution flattens nested Instructions with shallow overrides
- **scope:** `Jido.Instruction.resolve/3`, `Jido.Instruction.normalize!/3`
- **must:** Preserve the exact final target. Flatten nested Instructions. Outer call data replaces equal inner keys, and call-site parameters and context replace equal stored keys. Keep merges shallow. Preserve metadata during call-site resolution and keep it separate from execution policy. Reject invalid stored call data and normalize supported nil and keyword data.
- **kind:** functional
- **status:** active

### jido_action.instruction.I5 — Current target behavior determines the kind
- **scope:** `Jido.Instruction.resolve/3`, `Jido.Instruction.new/1`, `Jido.Instruction.bind/4`
- **must:** Classify Action modules, Flow modules, and runtime Flow values with their exact target values. Module targets must declare exactly one supported behavior. Callback names alone do not classify a target. Read the current module each time and refresh stale retained kinds. Reject unknown or ambiguous targets with configuration errors and useful target and reason details.
- **kind:** functional
- **status:** active

### jido_action.instruction.I6 — Validation checks executable callbacks without running work
- **scope:** `Jido.Instruction.validate/1`, `Jido.Instruction.validate_resolved/1`
- **must:** Resolve the current target before validation. Require run/2 for Action modules, flow/0 for Flow modules, and validate_params/1 and validate_output/1 for both. Runtime Flow values are accepted. A Flow module does not need run/2. Return structured errors for missing callbacks and malformed resolved Instructions. Include the affected target or Instruction and the reason. Validation must not execute Action work or Flow construction.
- **kind:** functional
- **status:** active
