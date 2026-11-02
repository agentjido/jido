---
modules: [Jido.Action.Output]
---
# Output envelope obligations

## Purpose

Check intentional non-map Action success values. These obligations refine
`ACT-004`. The API source remains `Jido.Action.Output` and the outputs guide.

### jido_action.output.I1 — Constructors retain the output kind, value and metadata
- **scope:** `Jido.Action.Output.raw/2`, `Jido.Action.Output.stream/2`, `Jido.Action.Output.batch/2`, `Jido.Action.Output.opaque/2`
- **must:** Build raw, stream, batch and opaque envelopes with the exact supplied value and map metadata. Default metadata to an empty map. Reject malformed options, unknown options, invalid metadata and values that are not permitted for the chosen kind with ArgumentError. Construct and validate stream envelopes without consuming the Enumerable; keep the original value and metadata.
- **kind:** functional
- **status:** active

### jido_action.output.I2 — Validation rejects malformed envelopes with the original value
- **scope:** `Jido.Action.validate_output/1`, `Jido.Exec.run/4`
- **must:** Preserve valid envelopes. Reject unsupported kinds, invalid metadata, improper batches, non-enumerable streams and non-envelope values with InvalidInputError. Keep the affected envelope or value in the error details.
- **kind:** functional
- **status:** active
