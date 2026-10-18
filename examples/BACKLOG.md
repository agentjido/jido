# Example updates

Keep example numbers stable. Test one example at a time. Stop at the next
failure and review its lesson before changing it.

- Update local runtime directives in multi-agent and causal trace examples.
- Update remaining Agent construction, Server replies, and readiness checks.
- Keep Plugin callbacks in one module when separate modules add no value.
- Validate each retained example, its failure case, and owned process cleanup.
- Run the complete example suite after the individual examples pass.

Factory and Elastic Group moved to `examples/jido_lab/experiments/jido_core`
in the workspace. They require separate application API updates there.
