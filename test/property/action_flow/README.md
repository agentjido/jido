# Action and Flow property and fuzz tests

Run the current property and fuzz suites from the package root:

```sh
mix test.property test/property/action_flow
mix test.fuzz test/property/action_flow
```

The current suite covers `Jido.Expr`. It checks the fixed operator set,
short-circuit behavior, parser limits, and bounded generated expression trees.
The required fuzz case list contains only `expression_trees`.

`mix test.fuzz` runs the full-report gate after the tests. A focused Action and
Flow fuzz run checks only the Action and Flow report.

## Reports

The fuzz run writes `_build/test/action-flow-property-report.json`. The report
must finish, pass, and contain a measurement for each current required fuzz
case. Focused property runs can create a partial report and do not use the full
fuzz gate.

Reduced failures use
`_build/test/action-flow-property-counterexamples/<case-id>`. Review a failure
before you remove it. Promote a useful input into a fixed regression test.

## Limits

The suite does not contain generated Action, Flow, or Exec recovery cases.
Focused deterministic tests own current crash and recovery coverage. Add a new
required fuzz ID only when its current test and measurement are both in
`test/property/action_flow`.
