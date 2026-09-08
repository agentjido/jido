> Subsystem review index. This document is pending approval.

# 05 — Plugins

Current comparison: [gap analysis](gap-analysis.md).

Plugins extend Agent state and Turn behavior and can add live Agent Server
work. The current `Jido.Plugin` behavior contains both pure callbacks and live
runtime callbacks.

Documents:

- [Plugin model](plugins.md)
- [Plugin facets and extension ownership](plugin-facets.md)
- [Scheduled occurrence identity and delivery](scheduled-occurrences.md)

The facet proposal assigns pure Turn work to an Agent facet, live process work
to an Agent Server facet, durable state conversion to a Persistence facet, and
definition planning to a Topology facet. The package manifest stays neutral.
Adapters, authoring extensions, Directives, and Telemetry remain separate
contracts.

Main alignment questions:

- Does one behavior remain, or does it split by owning subsystem?
- What Agent fields can one Plugin observe?
- Does each Plugin own an isolated prepared input?
- How are state keys and Directive types assigned to one owner?
- What data enters runtime Init and post-commit Directive context?
- How does a replacement runtime get current committed state and version?
