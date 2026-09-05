# Port a custom Strategy

The Strategy callback contract is removed. Express domain transitions in an
Action or Flow, route a Signal to it, and return the complete next state.
Move runtime resources and typed effects into an explicit Plugin.

A custom Strategy that mutates Agent internals or Server state needs a rewrite.
No compatibility shim or replacement Strategy pipeline is supplied.
See [execution after V2](strategies.md) and [Plugins](plugins.md).
