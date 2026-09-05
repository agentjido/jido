# Errors

Public failures use tagged tuples and structured exceptions. A validation error
can identify an input, action, configuration, or complete-state size limit.
A routing error means that the Signal did not select one valid executable.
A caller timeout does not imply that active work was cancelled.

Call `Jido.Error.to_map/1` for transport. It keeps scalar path leaves at the
container depth limit, so field names and list indexes remain useful. Its bounded
projection also handles hostile binaries and redacts sensitive fields.

A pre-commit failure retains the previous Agent and revision. A directive failure
retains the new commit. Review `Jido.Agent.Turn.Outcome` and runtime error policy
to choose the application response. An uncertain persistence write stops the
writer even when ordinary error policy would continue.

See [transport regressions](../test/jido/error_transport_test.exs) and
[state-size checks](../test/jido/agent/state_budget_test.exs).
