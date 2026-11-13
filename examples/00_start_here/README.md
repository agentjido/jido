# 00 Start Here

Build one expense-approval application in six small lessons. Each lesson runs
offline and has its own behavior test.

1. [Validated state](00_01_validated_state/README.md) defines the Agent state.
2. [Submit Action](00_02_submit_action/README.md) validates one unit of work.
3. [Triage Flow](00_03_triage_flow/README.md) composes the Action in a Flow.
4. [Routed Agent](00_04_routed_agent/README.md) routes a Signal to the Flow.
5. [Hosted Agent](00_05_hosted_agent/README.md) runs the same behavior in AgentServer.
6. [Runtime inspection](00_06_runtime_inspection/README.md) observes a wait,
   commit, effect, and failed Turn.

Run the chapter:

```sh
mix test.examples examples/00_start_here --warnings-as-errors
```

The chapter does not use an AI model, network service, or credential.
