# Topology after V2 Pods

The V2 Pod structs, mutation planner, mutable runtime, topology state, and mutation
directives are removed. Use static `Jido.Topology` for composition and owned
children for Agent lifecycle. Fixed and Elastic Group examples show application
recovery, but they do not provide a compatible Pod mutation API.

Live edits to arbitrary graphs need a separate design and are outside this
migration. Port callers against the supported operations in
[orchestration](orchestration.md). The old source and tests remain in Git history.
