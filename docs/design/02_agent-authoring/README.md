> Subsystem review index. This document is pending approval.

# 02 — Agent authoring

Current comparison: [gap analysis](gap-analysis.md).

Agent authoring owns the Spark DSL, inline Actions, map and keyword forms,
Builder, Codec, trusted Registry, generated interfaces, and authoring
extensions. All supported forms must produce the same validated Agent
definition.

Documents:

- [Authoring proposal and history](authoring.md)
- [Implemented DSL and interface contract](dsl-and-interfaces.md)

Main alignment questions:

- Which authoring forms remain supported for V3?
- How does each form record and check definition revision?
- Which validation runs at compile time and which runs at construction?
- How do Agent and Topology extensions lower to canonical values?
