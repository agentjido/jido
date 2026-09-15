# Write a Plugin

Start with a callback-free package that uses `Jido.Plugin`. Add only the owner
facets that the capability needs.

Use `Jido.Agent.Plugin` for owned state and owned Directives. Use
`Jido.AgentServer.Plugin` only for live admission or runtime
work. Add `Jido.Persistence.Plugin` only when one owned state value needs a
format conversion. Add `Jido.Topology.Plugin` only for static canonical
Topology entries.

For owned state, declare a key and schema through `state_spec/1`. Implement
`reduce/2` to compute the complete next owned value. The reducer can read the
prior and candidate Agent states, the pure prepared input, and all validated
Directives. Keep Agent domain keys under the Action's control.

For a typed effect, implement `Jido.Agent.Directive` on the Directive module and
declare the type in the Agent facet. Put post-commit handling in the Agent
Server facet. Add `child_spec/1` only when the capability needs one permanent
runtime root.

For a live projection of owned state, use the optional Server
`after_commit/3` hook. It receives the exact committed owned value and revision
without a Directive from each Action. Initialize the projection from `Init`
on startup and replacement. Use semantic Telemetry if you only need observation.

See [the callback guide](plugins.md) and
[the four-facet tests](../test/jido/plugin/facets_test.exs).
