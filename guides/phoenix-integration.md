# Phoenix integration boundary

Supervise a named Jido instance with the Phoenix application. Keep request
validation and authorization in the application. Send validated Signals to the
selected Agent. Treat a call reply as a commit result, and model later external
completion separately.

LiveView processes can attach to an Agent to prevent idle shutdown while in use.
Owner death removes the attachment. Avoid persisting sockets, PIDs, or request
process state in Agent checkpoints.

This migration does not validate a Phoenix package integration or supply a V2
adapter. See [runtime controls](runtime.md), [scope](multi-tenancy.md), and
[downstream migration notes](migration.md).
