# Department Factory

Feature ID: `06_03_department_factory`. Status: implemented within the tested scope.

The factory runs a fixed dependency plan through Research, Design, Build, and
Quality Agents. Each head calls ReqLLM and produces a text artifact. At most
two steps run at once. Result identity, pause, cancellation, failure, and
seven-Agent shutdown are tested. Durable replay, real code execution, and
delivery are future work in the larger orchestrator plan.

[Source](../../../../lib/examples/06_factory/06_03_department_factory/orchestrator.ex) ·
[Tests](../../../../test/examples/06_factory/06_03_department_factory/orchestrator_test.exs) ·
[Plan](../../../../lib/examples/06_factory/orchestrator-plan.md)
