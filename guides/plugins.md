# Plugins

Declare Plugins explicitly in the Agent definition. `use Jido.Plugin` supplies
the V3 behavior. A Plugin can implement these separate operations:

- `prepare(command, opts)` changes permitted Signal or caller context input.
- `admit(runtime, command, opts)` controls live admission.
- `state_spec(opts)` declares one owned state key and schema.
- `update_state(owned_state, directives, opts)` returns the next owned value.
- `directives(opts)` and `validate_directive/2` declare and validate owned directives.
- `dispatch(runtime, directive, context, opts)` performs directive work after commit.

Optional `child_spec/1` starts an owned runtime. Without a runtime the dispatch
callback receives `nil`. Both forms use a supervised dispatch task and the same
validation, ordering, timeout, and failure rules. A replacement runtime starts
from current committed Plugin state.

The Action cannot change protected Plugin keys. A Plugin cannot replace the
Agent value. Plugin declarations are validated when the Agent value is built.
Old manifests, mounts, dependency requirements, and V2 callbacks require a port.

See the [Plugin example](https://github.com/agentjido/jido/tree/v3-spike/examples/01_basic/README.md),
[contract tests](../test/jido/agent/plugin_test.exs), and
[runtime tests](../test/jido/agent/plugin_runtime_test.exs).
