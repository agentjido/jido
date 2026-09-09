# Command and commit

Direct execution is `Jido.Agent.cmd(agent, signal, options)`. Success returns
`{:ok, candidate_agent, directives}`. It starts no Agent Server and does not
commit a live state or dispatch the returned directives.

For live execution, start an Agent under a Jido instance. Send the Signal through
`Jido.AgentServer.call/3`, `cast/2`, or `send_request/3`. A call returns
`{:ok, committed_agent}` after commit. A pre-commit failure returns
`{:error, reason}`. A successful cast confirms sending only.

The Server serializes admission, execution, commit, and directive work. Jido
selects the first executable from the unchanged source Signal. Plugins can then
prepare command input, but they cannot replace the selection. The Runner
protects Plugin-owned state, validates Directives, applies Agent Plugin
contributions, and validates the complete candidate.
The Server commits before dispatch. A failed directive preserves that commit
and stops later directives in its batch. Error policy then applies.

See `Jido.Action`, [Plugins](plugins.md), and [runtime controls](runtime.md).
