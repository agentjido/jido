# Waiting for results

The V2 Await facade and status-based polling helpers are removed. Use
`AgentServer.call/3` for a commit reply. Use `send_request/3` and
`receive_response/2` when sending and waiting must be separate. Use
`await_ready/2` for runtime startup readiness.

A command commit does not prove that later external work has finished. Model
that completion as a Signal and a later committed state. A caller timeout does
not undo active work. Use the supported cancellation API when cancellation is
required. See [runtime controls](runtime.md).
