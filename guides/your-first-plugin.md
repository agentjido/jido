# Write a Plugin

Start with a callback-free package that uses `Jido.Plugin`. Add only the owner
facets that the capability needs.

Use `Jido.Agent.Plugin` for owned state and owned Directives. Use
`Jido.AgentServer.Plugin` only for live admission or runtime
work. Add `Jido.Persistence.Plugin` only when one owned state value needs a
format conversion. Add `Jido.Topology.Plugin` only for static canonical
Topology entries.

For owned state, declare a key and schema through `state_spec/1`. Implement
`update_state/3` to reduce owned Directives into the complete next owned value.
Keep Agent domain keys under the Action's control.

For a typed effect, declare and validate the Directive in the Agent facet. Put
post-commit handling in the Agent Server facet. Add `child_spec/1` only when the
capability needs one permanent runtime root.

See [the callback guide](plugins.md) and
[the four-facet tests](../test/jido/plugin/facets_test.exs).
