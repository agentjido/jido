# 05.02 Restart Recovery

The Flow opens a wait. Its Jido instance then stops and starts again with the
same namespace and persistence adapter. `Jido.Durable.status/2` restores the
same wait ID. `Jido.Durable.signal/5` saves an approval Signal for that wait
and continues the Flow.

Confirmed authored component boundaries do not repeat. Work inside one
unfinished composite component can repeat after recovery.
