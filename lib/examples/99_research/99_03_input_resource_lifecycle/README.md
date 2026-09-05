# CTRL-01: input and resource lifecycle

Status: **planned**.

Use a provider-neutral input Plugin that emits typed Signals and owns a
disposable resource. Reconnect it, rebuild desired subscriptions, and close it
without leaked processes or repeated committed effects.

Bus Delivery and Managed Jobs are the starting points. Vendor connections do
not prove this lifecycle contract.

[Research queue](../README.md) ·
[Acceptance notes](../../../../test/examples/99_research/99_03_input_resource_lifecycle/README.md)
