> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# DIST-02: remote lifecycle failure and cleanup

Date: **2026-09-04**. Status: **Implemented with current core**.

The [Remote Lifecycle Agent](../../examples/05_multi_agent/05_06_remote_lifecycle/remote_lifecycle.ex)
records a child exit as `:exited`, except when the monitor reports
`:noconnection`. It records that result as `:unreachable`. It does not infer a
remote process death from lost connectivity.

```shell
mix test test/jido/agent/remote_lifecycle_test.exs --seed 0
```

All **four tests pass, with no skips**:

1. A connected remote process exit carries its observed `:killed` reason.
2. Remote node loss reports `:noconnection`; the parent remains available.
3. A distribution disconnect leaves both VMs alive. The default parent-loss
   policy stops the remote Agent and its held execution task. Reconnect does
   not create another child automatically. Explicit requests resolve the old
   closed receipt, then start a new generation. A delayed old online message
   cannot replace the new child.
4. Parent node loss stops its child Agent and the child's execution task.

The tests use separate peer control channels. `Node.disconnect/1` breaks the
real Agent connection without stopping either VM. Checks run on the local
node of each process. The stale-message check sends the injected message and
reads children from the same sender, so the assertion follows its processing.

DIST-01 also retains its 16 tests for permanent remote restart, startup failure,
parent process loss, explicit stop, and duplicate creation receipts. This adds
failure and observation cases without changing core.

The default child policy stops work after connection loss. This is a policy,
not evidence that the parent died. There is no automatic failover, distributed
lease, or durable ownership record. These tests do not simulate packet loss,
asymmetric links, or a multi-host deployment. DIST-03 retains those authority
questions. Explicit retry after reconnect currently needs two requests when
the first resolves a closed receipt; that result is a post-commit failure,
not a failed business-state commit.
