> Pending approval. Selected decisions are recorded below.

# 02 — Agent authoring

## Briefing

Current Jido supports Agent modules with DSL blocks, direct map or keyword
configuration, and Codec documents. These forms use the canonical Agent
constructor. The user intentionally removed Builder. Module definitions use
blocks for schema, metadata, Plugins, and routes. Standalone module options
are limited to name, description, vsn, and extensions.

An exposed route declares a helper name with `as:`. The generated helper
builds a Signal from a plain input map and optional envelope settings.
Direct Agent evaluation and live Server execution use their normal public
entry points. The earlier `define` syntax, positional arguments, bang Signal
helpers, and generated live-call helpers are removed from the design contract.

Direct map and keyword data remain supported. Codec encodes a validated
neutral definition and uses the shared trusted Registry. It excludes live
identity and state. This review does not approve the complete topic documents.

## Why this seam exists

- Owner: the Agent authoring boundary.
- Owns: module blocks, inline route Actions, Signal helpers, Codecs, trusted
  Registry use, normalization, and static extension lowering.
- Adjacent owners: Agent values belong to topic 01; execution belongs to
  jido_action; Signal behavior belongs to jido_signal; live calls belong to 08.

## Current and selected contracts

| Area | Contract |
| --- | --- |
| Module authoring | Keep DSL blocks and the four allowed module options. |
| Route helpers | Keep named Signal constructors with map input; execution remains explicit. |
| Direct data | Keep map and keyword definition construction. |
| Builder | Removed by explicit user decision; older references need cleanup. |
| Codec | Keep trusted decode and definition-first encoding. |
| Module authority | Use definition/0; actual compiler metadata stays private. |

## Major gaps and work remaining

| Gap | Required outcome | Owner |
| --- | --- | --- |
| Historical evidence | Refresh remaining acceptance mapping against the selected V3 API. | 02 Agent authoring |
| GAP-001 | Remove remaining Builder requirements and historical parity claims. | 00, 01, 02, 11, 90 |
| Evidence | Replace historical acceptance claims with current source and test mapping. | 02, 99 |
| Shared errors | Reconcile authoring result shapes with the selected error contract. | 12 |

## Selected decisions

- GAP-009: Keep V3 module blocks; direct keyword data is still supported.
- GAP-010: Name Signal helpers on routes with as; remove the earlier define API.
- GAP-012: Require plain maps in both default forms; remove the struct exception.
- GAP-001: Keep Builder removed.

The inline lookup name and private metadata inventory are corrected in the
design under GAP-011/013. Codec evidence paths are corrected under GAP-014.
These source-based corrections do not introduce new APIs.

## Documents

- [Target design](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/02_agent-authoring/design.md)
- [Alignment](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/02_agent-authoring/alignment.md)
- [Numbered review](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/GAP_ANALYSIS.md)
