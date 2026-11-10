---
modules: [Jido.Expr, Jido.Expr.Parser, Jido.Expr.Runtime, Jido.Expr.Limits, Jido.Expr.Error]
---
# Expression obligations

## Purpose

These obligations refine `EXPR-001` and `EXPR-002`. The Expr module
documentation defines the supported grammar, operations, callbacks and limits.

### jido_action.expression.I1 — Fixed operations retain native Elixir meaning
- **scope:** `Jido.Expr.operations/0, Jido.Expr.new/2, Jido.Expr.evaluate/2`
- **must:** The closed operator and arity set retains documented Elixir arithmetic, comparison, strict membership, selection, concatenation and Boolean result rules. Binary Boolean operations resolve operands in order and skip only unneeded operands. Resolved expression-shaped data is data and is not executed again. Unknown operators and wrong or oversized arities return structured errors.
- **kind:** functional
- **status:** active

### jido_action.expression.I2 — Source parsing and the macro keep a closed grammar
- **scope:** `Jido.Expr.parse/2, Jido.Expr.parse!/2, Jido.Expr.expr/1`
- **must:** Parse the supported source grammar and precedence into canonical expressions. Hosts can supply reference leaves; explicit variable pins insert trusted host data in the macro. Reject unsupported roots, general executable Elixir, assignments, remote calls and unsupported aliases without running work. The raising APIs raise the structured expression error.
- **kind:** functional
- **status:** active

### jido_action.expression.I3 — Host traversal preserves paths and callback rules
- **scope:** `Jido.Expr.normalize/2, Jido.Expr.reduce/4, Jido.Expr.validate/2, Jido.Expr.evaluate/2`
- **must:** Normalization and reduction visit supported expressions, containers and host leaves at their exact paths. Normalize each incoming host value once without executing operations. Respect reducer continuation and halt results. Validate or resolve host callbacks only at their admitted arities, retain host errors and relative expression error paths, and contain unsupported callback returns with structured errors. Expression error details must not disclose runtime operand values.
- **kind:** functional
- **status:** active

### jido_action.expression.I4 — Resource and option limits bound all expression work
- **scope:** `Jido.Expr.parse/2, Jido.Expr.normalize/2, Jido.Expr.reduce/4, Jido.Expr.validate/2, Jido.Expr.evaluate/2`
- **must:** Validate every public option and apply the documented depth, node, binary-byte and integer-bit limits. Budgets include operands, callback replacement data, generated output, comparison and membership work. Keep cumulative budgets and the first failing data path. Stop before a host callback after a budget is exhausted. Scalar roots are not standalone expressions.
- **kind:** functional
- **status:** active
