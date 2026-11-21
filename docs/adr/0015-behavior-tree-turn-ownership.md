# ADR 0015 Behavior Tree Turn ownership

- Status: Proposed
- Date: 2026-11-21

## Context

The standalone Jido v2 package uses an Agent Strategy to run tree ticks and
collect effects. A v3 Agent runs Actions and Flows through a Turn. A Plugin
owns each field that the Plugin contributes to Agent state.

## Decision

Bundle the tree engine in the capabilities layer. Use an opt-in Plugin to
contribute command routes, own continuation state, and reduce one tree-state
Directive per command. Leaf Actions return candidate changes and Directives
through the ordinary Turn path.

## Consequences

AgentServer validates the complete state and dispatches Directives after
commit. A running tree resumes on its next tick Signal. Standalone execution
continues through local entry points. Applications migrate the dependency and
Strategy in the same change because the packages share module names.

## References

- [Behavior Tree guide](../../guides/built-in-plugins/behavior-trees.md)
- [Behavior Tree obligations](../../test/contracts/jido.plugin/behavior_tree.obligations.md)
