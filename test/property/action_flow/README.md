# Action and Flow property and fuzz tests

Run the current property and fuzz suites from the package root:

```sh
mix test.property test/property/action_flow
mix test.fuzz test/property/action_flow
```

The current suite covers `Jido.Expr`. It checks the fixed operator set,
short-circuit behavior, parser limits, and bounded generated expression trees.
The required fuzz case list contains only `expression_trees`.

`mix test.fuzz` runs the full-report gate after the tests. A focused Expr run
checks only the selected family.

## Reports

All property families write `_build/test/property-report.json`. A full fuzz run
must finish, pass, and contain every configured Signal, Expr, and AgentServer
measurement. Focused runs can contain only their selected family.

Reduced failures use
`_build/test/property-counterexamples/jido_expr/<case-id>`. Review a failure
before you remove it. Promote a useful input into a fixed regression test.

## Limits

The suite does not contain generated Action, Flow, or Exec recovery cases.
Focused deterministic tests own current crash and recovery coverage. Add a new
required fuzz ID only when its current test and measurement are both in
`test/property/action_flow`.
