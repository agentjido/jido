# 06 AgentServer

These offline lessons host one Agent as a supervised actor and show one Turn
lifecycle.

1. [Start and Address](06_01_start_and_address/README.md) starts a Jido instance
   and one supervised Agent activation.
2. [Pure and Hosted Execution Parity](06_02_pure_hosted_parity/README.md)
   compares candidate state and reply data across both modes.
3. [Request Modes](06_03_request_modes/README.md) compares call, cast, submit,
   await, overload, and admission deadlines.
4. [Turn Result](06_04_turn_result/README.md) makes accepted failure an explicit
   result without changing committed state.
5. [Commit Before Effects](06_05_commit_before_effects/README.md) injects a
   Plugin effect failure after revision 1 commits.
6. [Turn Control](06_06_turn_control/README.md) covers cancellation, quiesce,
   and resume.
7. [Managed Jobs](06_07_managed_jobs/README.md) starts linked work after commit.
8. [Runtime Inspection](06_08_runtime_inspection/README.md) uses public status
   and snapshot operations.
9. Hibernation and thaw are covered in
   [Persistence](../12_persistence/12_02_hibernate_and_thaw/README.md).
10. [Definition Changes](06_10_definition_changes/README.md) replaces one idle
    activation with a trusted definition and migrated state.

Run the current chapter with:

```sh
mix test.examples examples/06_agent_server --warnings-as-errors
```

Expected result: all AgentServer examples pass without network access or
credentials.

## Limits

AgentServer owns the current process, serialization, commit, and managed
effects. The Agent owns domain decisions. Durable process and BEAM recovery
belong to chapter 13.
