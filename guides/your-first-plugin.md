# Write a Plugin

Start with `use Jido.Plugin`. Implement only the capability's required callbacks.
For owned state, declare a key and schema through `state_spec/1`, then return
`{:ok, next_owned_state}` from `update_state/3`. Keep the Agent's domain keys
under the Action's control.

For a typed effect, declare its directive, validate it, and implement
`dispatch/4`. Add a child specification only when the capability needs a runtime.
Test direct preparation, live dispatch, failure policy, replacement, and cleanup.

See [the callback guide](plugins.md) and
[stateless dispatch tests](../test/jido/agent/stateless_directive_test.exs).
